@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import HaishinKit
import RTMPHaishinKit

actor HaishinKitBroadcaster: Broadcasting {
    /// Roughly three seconds at the one-second sampling interval, which keeps
    /// detection of a silent publish inside the budget for entering Reconnecting.
    private static let silentSamplesBeforeDrop = 3

    var events: AsyncStream<BroadcastEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: BroadcastEvent.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { _ in
            Task { await self.removeSubscriber(id) }
        }
        return stream
    }

    private let mixer = MediaMixer(captureSessionMode: .single)
    private var subscribers: [UUID: AsyncStream<BroadcastEvent>.Continuation] = [:]
    private var connection: RTMPConnection?
    private var stream: RTMPStream?
    private var statusTasks: [Task<Void, Never>] = []
    private var preparedQuality: StreamQuality?
    private var previewOutput: MTHKView?
    private var cameraPosition: CameraPosition = .back
    private var availablePositions: Set<CameraPosition> = []
    private var isMicrophoneRequested = false
    private var isMicrophoneAttached = false
    private var isPublishing = false
    private var hasSentBytes = false
    private var silentSamples = 0
    private var monitorTasks: [Task<Void, Never>] = []

    /// Opening a connection takes seconds, and the actor admits `stop()` and
    /// `teardown()` at every await inside it. Each of those ends the session, so a
    /// connection that opens afterwards belongs to nobody: it is closed instead of
    /// being reported as a live broadcast.
    private var session = 0

    /// Audio reaches the destination only when the app asked for it *and* the device
    /// is attached, which it is not between broadcasts.
    private var isMicrophoneActive: Bool {
        isMicrophoneRequested && isMicrophoneAttached
    }

    func prepare(quality: StreamQuality) async throws {
        if preparedQuality != nil {
            if let previewOutput {
                await mixer.addOutput(previewOutput)
            }
            return
        }

        availablePositions = discoverCameras()
        if !availablePositions.contains(cameraPosition) {
            if availablePositions.contains(.back) {
                cameraPosition = .back
            } else if availablePositions.contains(.front) {
                cameraPosition = .front
            }
        }

        guard let camera = cameraDevice(for: cameraPosition) else {
            throw BroadcastError.noCameraAvailable
        }

        let formats = Self.supportedFormats(from: camera)
        if case .unsupported(let reason) = quality.validated(against: formats) {
            throw BroadcastError.unsupportedQuality(reason: reason)
        }

        try await attachCamera(camera, position: cameraPosition)
        await mixer.setVideoOrientation(.portrait)
        await configureEncodedScreen(size: quality.encodedVideoSize)
        try await mixer.setFrameRate(Float64(quality.frameRate))
        await mixer.startRunning()
        preparedQuality = quality
        startMonitors()
    }

    func attachPreview(_ surface: PreviewSurface) async {
        guard let preview = surface.view as? MTHKView else { return }
        if previewOutput !== preview, let previewOutput {
            await mixer.removeOutput(previewOutput)
        }
        previewOutput = preview
        await mixer.addOutput(preview)
    }

    /// The only place a drawing can be added to the outgoing picture.
    ///
    /// `mixer.screen` is HaishinKit's compositor. A clock overlay is a
    /// `TextScreenObject` attached here with `try mixer.screen.addChild(_:)`.
    /// That change stays in this file: it does not touch `Broadcasting`,
    /// `BroadcastState`, or any view.
    ///
    /// This version sets the encoded size and attaches nothing.
    private func configureEncodedScreen(size: CGSize) async {
        await Task { @ScreenActor in
            mixer.screen.size = size
            // Overlay seam: try mixer.screen.addChild(TextScreenObject())
        }.value
    }

    func start(to credentials: StreamCredentials) async throws {
        let attempt = session

        // The microphone is released between broadcasts, so a start that follows a
        // stop — including the automatic reconnection attempt — attaches it again.
        if isMicrophoneRequested {
            await attachMicrophoneIfNeeded()
            await setAudioMuted(!isMicrophoneActive)
        }

        let quality = preparedQuality ?? .preset720p30
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        self.connection = connection
        self.stream = stream

        do {
            try await stream.setVideoSettings(
                VideoCodecSettings(
                    videoSize: quality.encodedVideoSize,
                    bitRate: quality.videoBitrate,
                    expectedFrameRate: Double(quality.frameRate)
                )
            )
            try await stream.setAudioSettings(AudioCodecSettings(bitRate: quality.audioBitrate))
            await mixer.addOutput(stream)

            _ = try await connection.connect(credentials.ingestURL.absoluteString)
            _ = try await stream.publish(credentials.streamKey)

            guard attempt == session else {
                await discard(stream: stream, connection: connection)
                return
            }

            isPublishing = true
            listenForStatus(on: connection, stream: stream)
            startStatisticsSampling(stream: stream, quality: quality)
            emit(.publishing)
        } catch {
            let mapped = Self.mappedError(error)
            guard attempt == session else {
                await discard(stream: stream, connection: connection)
                return
            }
            emit(.failed(mapped))
            await tearDownConnection()
            throw mapped
        }
    }

    func stop() async {
        session += 1
        guard isPublishing || connection != nil else { return }
        await tearDownConnection()
        await releaseMicrophone()
    }

    func captureConfiguration() -> CaptureConfiguration {
        CaptureConfiguration(
            cameraPosition: cameraPosition,
            isMicrophoneEnabled: isMicrophoneActive,
            availableCameraPositions: availablePositions
        )
    }

    func switchCamera(to position: CameraPosition) async throws {
        guard availablePositions.contains(position) else {
            throw BroadcastError.noCameraAvailable
        }
        guard let camera = cameraDevice(for: position) else {
            throw BroadcastError.noCameraAvailable
        }
        try await attachCamera(camera, position: position)
        cameraPosition = position
    }

    func setMicrophoneEnabled(_ enabled: Bool) async {
        isMicrophoneRequested = enabled
        if enabled {
            await attachMicrophoneIfNeeded()
        }
        await setAudioMuted(!isMicrophoneActive)
    }

    /// Attaching a device reconfigures the capture session shared with video, which
    /// stalls the picture while it happens. The microphone is therefore attached at
    /// most once per broadcast and released when that broadcast stops; silencing it
    /// mid-broadcast is a mixer flag instead.
    ///
    /// The audio session is activated here rather than in `prepare(quality:)`:
    /// activating a `.playAndRecord` session is itself a use of the microphone and
    /// makes the system ask for access, which is only acceptable from this moment —
    /// the first time a broadcast actually needs sound.
    private func attachMicrophoneIfNeeded() async {
        guard !isMicrophoneAttached else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let microphone = AVCaptureDevice.default(for: .audio)
        else {
            return
        }
        do {
            try await configureAudioSession(active: true)
            try await mixer.attachAudio(microphone)
            isMicrophoneAttached = true
        } catch {
            isMicrophoneAttached = false
        }
    }

    /// A stopped broadcast releases the microphone, so the system stops indicating
    /// audio use as soon as one ends. The camera is
    /// not released here: the preview outlives the broadcast, and nothing previews
    /// sound. What the user asked the control to do survives, so the next start —
    /// or the automatic reconnection attempt — restores audio without asking again.
    private func releaseMicrophone() async {
        guard isMicrophoneAttached else { return }
        isMicrophoneAttached = false
        try? await mixer.attachAudio(nil)
        try? await configureAudioSession(active: false)
    }

    private func setAudioMuted(_ muted: Bool) async {
        var settings = await mixer.audioMixerSettings
        guard settings.isMuted != muted else { return }
        settings.isMuted = muted
        await mixer.setAudioMixerSettings(settings)
    }

    func teardown() async {
        session += 1
        await tearDownConnection()
        if let previewOutput {
            await mixer.removeOutput(previewOutput)
            self.previewOutput = nil
        }
        await mixer.stopRunning()
        try? await mixer.attachVideo(nil)
        try? await mixer.attachAudio(nil)
        try? await configureAudioSession(active: false)
        stopMonitors()
        preparedQuality = nil
        availablePositions = []
        isMicrophoneRequested = false
        isMicrophoneAttached = false
        cameraPosition = .back
    }

    private func emit(_ event: BroadcastEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    private func tearDownConnection() async {
        isPublishing = false
        hasSentBytes = false
        silentSamples = 0
        statusTasks.forEach { $0.cancel() }
        statusTasks.removeAll()
        if let stream {
            await mixer.removeOutput(stream)
            _ = try? await stream.close()
        }
        try? await connection?.close()
        stream = nil
        connection = nil
    }

    /// Closes a connection that outlived the session it was opened for, without
    /// disturbing whatever the broadcaster is doing now.
    private func discard(stream: RTMPStream, connection: RTMPConnection) async {
        await mixer.removeOutput(stream)
        _ = try? await stream.close()
        try? await connection.close()
        if self.stream === stream {
            self.stream = nil
            self.connection = nil
        }
    }

    private func startStatisticsSampling(stream: RTMPStream, quality: StreamQuality) {
        statusTasks.append(Task {
            while !Task.isCancelled {
                await publishStatistics(from: stream, quality: quality)
                try? await Task.sleep(for: .seconds(1))
                guard isPublishing else { return }
            }
        })
    }

    private func publishStatistics(from stream: RTMPStream, quality: StreamQuality) async {
        let measuredBitsPerSecond = await stream.info.currentBytesPerSecond * 8
        let measuredFrameRate = Int(await stream.currentFPS)
        emit(
            .statistics(
                StreamStatistics(
                    videoBitrate: measuredBitsPerSecond > 0 ? measuredBitsPerSecond : quality.videoBitrate,
                    audioBitrate: quality.audioBitrate,
                    resolution: quality.encodedVideoSize,
                    frameRate: measuredFrameRate > 0 ? measuredFrameRate : quality.frameRate,
                    videoCodec: quality.videoCodec,
                    audioCodec: quality.audioCodec
                )
            )
        )
        trackThroughput(measuredBitsPerSecond)
    }

    /// A destination can accept the connection and then receive nothing, which no
    /// RTMP status code reports. Samples carrying no bytes are the only evidence
    /// available, so a publish that sent bytes and then went quiet is reported as a
    /// drop and follows the ordinary reconnect path. Samples before the first byte
    /// are ignored, because a publish that has only just started is legitimately
    /// silent.
    private func trackThroughput(_ bitsPerSecond: Int) {
        guard isPublishing else { return }
        if bitsPerSecond > 0 {
            hasSentBytes = true
            silentSamples = 0
            return
        }
        guard hasSentBytes else { return }
        silentSamples += 1
        guard silentSamples >= Self.silentSamplesBeforeDrop else { return }
        isPublishing = false
        emit(.disconnected)
    }

    private func listenForStatus(on connection: RTMPConnection, stream: RTMPStream) {
        statusTasks.append(Task {
            for await status in await connection.status {
                handle(status)
            }
        })
        statusTasks.append(Task {
            for await status in await stream.status {
                handle(status)
            }
        })
    }

    private func startMonitors() {
        guard monitorTasks.isEmpty else { return }
        monitorTasks.append(Task {
            for await notification in NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification
            ) {
                await handleAudioInterruption(notification)
            }
        })
        monitorTasks.append(Task {
            for await _ in NotificationCenter.default.notifications(
                named: AVCaptureSession.runtimeErrorNotification
            ) {
                await reportCameraUnavailable()
            }
        })
        monitorTasks.append(Task {
            for await notification in NotificationCenter.default.notifications(
                named: AVCaptureSession.wasInterruptedNotification
            ) {
                guard Self.isCameraTakenByAnotherApp(notification) else { continue }
                await reportCameraUnavailable()
            }
        })
    }

    private func stopMonitors() {
        monitorTasks.forEach { $0.cancel() }
        monitorTasks.removeAll()
    }

    /// A capture session is also interrupted by an ordinary move to the background,
    /// which is not a failure — that path ends the broadcast on its own.
    /// Only losing the camera to another client is reported to the user.
    private static func isCameraTakenByAnotherApp(_ notification: Notification) -> Bool {
        guard let rawValue = notification.userInfo?[
            AVCaptureSessionInterruptionReasonKey
        ] as? Int else {
            return false
        }
        return AVCaptureSession.InterruptionReason(rawValue: rawValue)
            == .videoDeviceInUseByAnotherClient
    }

    /// A camera that fails or is taken away mid-session is a failure like any other:
    /// it reaches the user as a message and a change of state rather than a frozen
    /// picture.
    private func reportCameraUnavailable() async {
        // Nothing to report when capture is not running: the notification then
        // belongs to the system tearing the session down, not to a lost camera.
        guard preparedQuality != nil else { return }
        isPublishing = false
        emit(.failed(.cameraUnavailable))
        await tearDownConnection()
        await releaseMicrophone()
    }

    private func handleAudioInterruption(_ notification: Notification) async {
        guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: rawValue) == .began
        else {
            return
        }
        guard isPublishing || connection != nil else { return }
        isPublishing = false
        emit(.failed(.audioSessionInterrupted))
        await tearDownConnection()
    }

    private func handle(_ status: RTMPStatus) {
        switch status.code {
        case RTMPConnection.Code.connectClosed.rawValue,
             RTMPStream.Code.connectClosed.rawValue:
            guard isPublishing else { return }
            isPublishing = false
            emit(.disconnected)
        case RTMPConnection.Code.connectRejected.rawValue,
             RTMPStream.Code.connectRejected.rawValue,
             RTMPStream.Code.publishBadName.rawValue:
            isPublishing = false
            emit(.failed(.destinationRejected(detail: status.code)))
        // These arrive only once publishing has begun, so the connection existed and
        // then failed — the device did not lack a network to begin with.
        case RTMPConnection.Code.connectFailed.rawValue,
             RTMPStream.Code.connectFailed.rawValue:
            isPublishing = false
            emit(.failed(.connectionLost))
        default:
            break
        }
    }

    private func attachCamera(_ camera: AVCaptureDevice, position: CameraPosition) async throws {
        try await mixer.attachVideo(camera) { videoUnit in
            if let connection = videoUnit.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
            }
            videoUnit.isVideoMirrored = position == .front
        }
    }

    private func discoverCameras() -> Set<CameraPosition> {
        var positions: Set<CameraPosition> = []
        for device in Self.discoverySession(position: .unspecified).devices {
            switch device.position {
            case .front: positions.insert(.front)
            case .back: positions.insert(.back)
            default: break
            }
        }
        return positions
    }

    private func cameraDevice(for position: CameraPosition) -> AVCaptureDevice? {
        let avPosition: AVCaptureDevice.Position = position == .front ? .front : .back
        let devices = Self.discoverySession(position: avPosition).devices
        return devices.first { $0.deviceType == .builtInWideAngleCamera } ?? devices.first
    }

    private static func discoverySession(position: AVCaptureDevice.Position) -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInDualCamera,
                .builtInDualWideCamera,
                .builtInTripleCamera,
                .builtInTrueDepthCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera,
            ],
            mediaType: .video,
            position: position
        )
    }

    private func configureAudioSession(active: Bool) async throws {
        try await MainActor.run {
            let session = AVAudioSession.sharedInstance()
            if active {
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.defaultToSpeaker, .allowBluetoothHFP]
                )
            }
            try session.setActive(active, options: active ? [] : .notifyOthersOnDeactivation)
        }
    }

    /// A destination that refuses the broadcast and a device with no network both
    /// arrive here as a failed connect, and telling the user the wrong one sends them
    /// to fix the wrong thing. They are separated by how far the attempt got: only a
    /// socket that never carried a conversation is the network. Once the server has
    /// answered — including by closing the connection after the handshake, which is
    /// what an unknown application path in the address looks like — the refusal is
    /// the destination's, and the address and key are what the user can act on.
    private static func mappedError(_ error: any Error) -> BroadcastError {
        if let error = error as? BroadcastError {
            return error
        }
        if let error = error as? RTMPConnection.Error {
            switch error {
            case .socketErrorOccurred:
                return .noNetwork
            case .connectionTimedOut, .requestTimedOut:
                return .connectionTimedOut
            case .requestFailed(let response):
                return .destinationRejected(detail: response.status?.code ?? "")
            case .invalidState, .unsupportedCommand:
                return .destinationRejected(detail: "")
            }
        }
        if let error = error as? RTMPStream.Error {
            switch error {
            case .requestFailed:
                return .destinationRejected(detail: "")
            case .unsupportedCodec:
                return .unsupportedQuality(reason: "Codec not available.")
            case .requestTimedOut:
                return .connectionTimedOut
            case .invalidState:
                return .connectionLost
            }
        }
        return .destinationRejected(detail: "")
    }

    private static func supportedFormats(from device: AVCaptureDevice) -> [SupportedCaptureFormat] {
        device.formats.map { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let rates = format.videoSupportedFrameRateRanges.flatMap { range in
                Int(range.minFrameRate.rounded(.up))...Int(range.maxFrameRate.rounded(.down))
            }
            return SupportedCaptureFormat(
                width: Int(dimensions.width),
                height: Int(dimensions.height),
                frameRates: Array(Set(rates)),
                maxVideoBitrate: Int.max,
                maxAudioBitrate: Int.max,
                videoCodecs: [.h264],
                audioCodecs: [.aac],
                supportsPortrait: true
            )
        }
    }
}
