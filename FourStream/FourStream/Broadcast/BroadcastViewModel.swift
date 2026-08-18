import Foundation

nonisolated struct BroadcastScreenState: Equatable, Sendable {
    var broadcast: BroadcastState
    var capture: CaptureConfiguration
    var elapsedTimeText: String
    var statistics: StreamStatistics?
    var microphoneAuthorization: AuthorizationStatus
}

@MainActor
final class BroadcastViewModel {
    private(set) var state: BroadcastScreenState
    let states: AsyncStream<BroadcastScreenState>

    var needsLeaveConfirmation: Bool {
        switch state.broadcast {
        case .connecting, .online, .reconnecting:
            true
        case .offline, .failed:
            false
        }
    }

    var preventsAutoLock: Bool {
        switch state.broadcast {
        case .connecting, .online, .reconnecting:
            true
        case .offline, .failed:
            false
        }
    }

    var isStatusTappable: Bool {
        if case .online = state.broadcast { true } else { false }
    }

    var isPreviewObscured: Bool {
        switch state.broadcast {
        case .failed, .reconnecting:
            true
        case .offline, .connecting, .online:
            false
        }
    }

    var failure: BroadcastError? {
        if case .failed(let error) = state.broadcast { error } else { nil }
    }

    var canOpenSystemSettings: Bool {
        if case .failed(let error) = state.broadcast {
            return error.offeredAction == .openSettings
        }
        return state.microphoneAuthorization == .denied
    }

    var isMicrophoneSilencedByAccess: Bool {
        switch state.microphoneAuthorization {
        case .denied, .restricted:
            true
        case .granted, .notDetermined:
            false
        }
    }

    private let credentials: StreamCredentials
    private let broadcaster: any Broadcasting
    private let mediaAuthorizer: any MediaAuthorizing
    private let connectDeadline: Duration
    private let reconnectDeadline: Duration
    private let clock = ContinuousClock()
    private let continuation: AsyncStream<BroadcastScreenState>.Continuation
    private var eventTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var captureTask: Task<BroadcastError?, Never>?
    private var preview: PreviewSurface?

    /// What the user wants the microphone to do, which is not the same thing as what
    /// the broadcaster is doing: nothing is attached until a broadcast needs it. It
    /// starts on, because a broadcast is expected to carry sound.
    private var isMicrophoneIntended = true
    private var isCapturePrepared = false
    private var isPreparingCapture = false
    private var isSwitchingCamera = false

    /// The two deadlines bound the two waiting states: 10 seconds for a first
    /// connection, 15 for the single reconnection attempt. They are injectable so
    /// both bounds can be exercised in a unit test without the test waiting them out.
    init(
        credentials: StreamCredentials,
        broadcaster: any Broadcasting,
        mediaAuthorizer: any MediaAuthorizing,
        connectDeadline: Duration = .seconds(10),
        reconnectDeadline: Duration = .seconds(15)
    ) {
        self.credentials = credentials
        self.broadcaster = broadcaster
        self.mediaAuthorizer = mediaAuthorizer
        self.connectDeadline = connectDeadline
        self.reconnectDeadline = reconnectDeadline
        state = BroadcastScreenState(
            broadcast: .offline,
            capture: CaptureConfiguration(
                cameraPosition: .back,
                isMicrophoneEnabled: true,
                availableCameraPositions: []
            ),
            elapsedTimeText: "",
            statistics: nil,
            microphoneAuthorization: mediaAuthorizer.status(for: .microphone)
        )
        let (stream, continuation) = AsyncStream.makeStream(of: BroadcastScreenState.self)
        self.states = stream
        self.continuation = continuation
        continuation.yield(state)
    }

    func appear(preview: PreviewSurface) async {
        self.preview = preview
        startListeningToBroadcaster()
        await startPreviewIfPossible()
    }

    func start() async {
        switch state.broadcast {
        case .connecting, .online, .reconnecting:
            return
        case .offline, .failed:
            break
        }

        switch mediaAuthorizer.status(for: .camera) {
        case .denied:
            apply(.failed(.cameraAccessDenied))
            return
        case .restricted:
            apply(.failed(.cameraAccessRestricted))
            return
        case .granted, .notDetermined:
            break
        }

        // Connecting is entered before the first suspension. The guard above is the
        // only thing standing between two quick taps and two broadcasts, so the
        // state must not still read Offline while preparation is in flight.
        apply(.startRequested)

        if let error = await performCapture(.prepare) {
            apply(.failed(error))
            return
        }

        // Stop, backgrounding or leaving the screen during preparation all end the
        // attempt; without these checks it would connect after being cancelled.
        guard case .connecting = state.broadcast else { return }
        await resolveMicrophoneForStart()

        guard case .connecting = state.broadcast else { return }
        try? await broadcaster.start(to: credentials)
    }

    func stop() async {
        switch state.broadcast {
        case .offline, .failed:
            return
        case .connecting, .online, .reconnecting:
            break
        }
        cancelReconnect()
        apply(.stopRequested)
        await broadcaster.stop()
    }

    func retryFailure() async {
        guard case .failed(let error) = state.broadcast else { return }
        switch error {
        case .noCameraAvailable, .cameraUnavailable:
            // Capture itself is what failed, so a retry rebuilds it rather than
            // connecting on top of a camera that is no longer there.
            await performCapture(.release)
            await startPreviewIfPossible()
        case .cameraAccessDenied, .cameraAccessRestricted, .microphoneAccessDenied,
             .unsupportedQuality:
            await startPreviewIfPossible()
        case .noNetwork, .destinationRejected, .connectionTimedOut, .connectionLost,
             .audioSessionInterrupted:
            await start()
        }
    }

    func dismissFailure() {
        guard case .failed = state.broadcast else { return }
        apply(.dismissed)
    }

    func switchCamera() async {
        guard !isSwitchingCamera, state.capture.canSwitchCamera else { return }
        let next: CameraPosition = state.capture.cameraPosition == .back ? .front : .back
        guard state.capture.availableCameraPositions.contains(next) else { return }

        isSwitchingCamera = true
        defer { isSwitchingCamera = false }

        do {
            try await broadcaster.switchCamera(to: next)
            await refreshCapture()
        } catch {
            await refreshCapture()
        }
    }

    func toggleMicrophone() async {
        let wantEnabled = !state.capture.isMicrophoneEnabled
        if wantEnabled {
            let status = await microphoneStatus()
            state.microphoneAuthorization = status
            guard status == .granted else {
                isMicrophoneIntended = false
                state.capture.isMicrophoneEnabled = false
                await broadcaster.setMicrophoneEnabled(false)
                publish()
                return
            }
        }
        isMicrophoneIntended = wantEnabled
        await broadcaster.setMicrophoneEnabled(wantEnabled)
        await refreshCapture()
    }

    func disappear() async {
        eventTask?.cancel()
        eventTask = nil
        stopTicker()
        cancelReconnect()
        apply(.confirmedLeavingScreen)
        await performCapture(.release)
    }

    func confirmLeaving() async {
        cancelReconnect()
        apply(.confirmedLeavingScreen)
        await performCapture(.release)
    }

    func didLeaveForeground() async {
        cancelReconnect()
        apply(.leftForeground)
        await performCapture(.release)
    }

    func didBecomeActive() async {
        refreshMicrophoneAuthorization()
        await startPreviewIfPossible()
    }

    private func startPreviewIfPossible() async {
        if isPreparingCapture { return }
        isPreparingCapture = true
        defer { isPreparingCapture = false }

        switch await mediaAuthorizer.requestAccess(to: .camera) {
        case .granted:
            if let error = await performCapture(.prepare) {
                apply(.failed(error))
            } else {
                clearCaptureFailure()
            }
        case .denied:
            apply(.failed(.cameraAccessDenied))
        case .restricted:
            apply(.failed(.cameraAccessRestricted))
        case .notDetermined:
            break
        }
    }

    /// A working preview answers the failures about capture and nothing else: a
    /// rejected destination or a lost connection still waits for the user.
    private func clearCaptureFailure() {
        guard case .failed(let error) = state.broadcast else { return }
        switch error {
        case .cameraAccessDenied, .cameraAccessRestricted, .noCameraAvailable, .cameraUnavailable:
            apply(.dismissed)
        case .microphoneAccessDenied, .unsupportedQuality, .noNetwork, .destinationRejected,
             .connectionTimedOut, .connectionLost, .audioSessionInterrupted:
            break
        }
    }

    private enum CaptureTransition {
        case prepare
        case release
    }

    /// Preparing and releasing capture are long chains of awaits inside the
    /// broadcaster, and an actor admits the next call at every one of them. Left to
    /// overlap — which backgrounding and returning does routinely — a release that
    /// began first finishes last and undoes a preparation that already succeeded,
    /// leaving the preview frozen on its final frame. Running them one after another
    /// is what makes that cycle survivable.
    @discardableResult
    private func performCapture(_ transition: CaptureTransition) async -> BroadcastError? {
        let previous = captureTask
        let task = Task { [weak self] () -> BroadcastError? in
            _ = await previous?.value
            guard let self else { return nil }
            switch transition {
            case .prepare:
                return await self.prepareCapture()
            case .release:
                await self.releaseCapture()
                return nil
            }
        }
        captureTask = task
        return await task.value
    }

    private func prepareCapture() async -> BroadcastError? {
        if isCapturePrepared { return nil }
        do {
            try await broadcaster.prepare(quality: .preset720p30)
        } catch let error as BroadcastError {
            return error
        } catch {
            // Anything the boundary did not name is a camera that would not start —
            // claiming the device has none would be a guess, and usually a wrong one.
            return .cameraUnavailable
        }
        if let preview {
            await broadcaster.attachPreview(preview)
        }
        isCapturePrepared = true
        await refreshCapture()
        return nil
    }

    private func releaseCapture() async {
        isCapturePrepared = false
        await broadcaster.teardown()
        await refreshCapture()
    }

    private func resolveMicrophoneForStart() async {
        switch state.microphoneAuthorization {
        case .denied, .restricted:
            state.capture.isMicrophoneEnabled = false
            await broadcaster.setMicrophoneEnabled(false)
            publish()
        case .granted:
            await broadcaster.setMicrophoneEnabled(isMicrophoneIntended)
        case .notDetermined:
            if isMicrophoneIntended {
                let status = await mediaAuthorizer.requestAccess(to: .microphone)
                state.microphoneAuthorization = status
                let enabled = status == .granted
                isMicrophoneIntended = enabled
                state.capture.isMicrophoneEnabled = enabled
                await broadcaster.setMicrophoneEnabled(enabled)
                publish()
            } else {
                await broadcaster.setMicrophoneEnabled(false)
            }
        }
    }

    /// The system asks the user once, so a request on every toggle only costs latency.
    private func microphoneStatus() async -> AuthorizationStatus {
        let status = mediaAuthorizer.status(for: .microphone)
        guard status == .notDetermined else { return status }
        return await mediaAuthorizer.requestAccess(to: .microphone)
    }

    private func refreshMicrophoneAuthorization() {
        let status = mediaAuthorizer.status(for: .microphone)
        guard status != state.microphoneAuthorization else { return }
        state.microphoneAuthorization = status
        if status != .granted {
            state.capture.isMicrophoneEnabled = false
        }
        publish()
    }

    private func refreshCapture() async {
        var capture = await broadcaster.captureConfiguration()
        switch state.broadcast {
        case .offline, .failed:
            // The broadcaster reports whether audio is actually attached, and it
            // never is until a broadcast needs it. Until then the control shows the
            // setting the user chose instead, so Start is not silent by default.
            capture.isMicrophoneEnabled = isMicrophoneIntended
        case .connecting, .online, .reconnecting:
            break
        }
        if isMicrophoneSilencedByAccess {
            capture.isMicrophoneEnabled = false
        }
        state.capture = capture
        publish()
    }

    private func startListeningToBroadcaster() {
        guard eventTask == nil else { return }
        eventTask = Task { [weak self] in
            guard let self else { return }
            let events = await self.broadcaster.events
            for await event in events {
                self.handle(event)
            }
        }
    }

    private func handle(_ event: BroadcastEvent) {
        switch event {
        case .publishing:
            apply(.publishingConfirmed)
        case .disconnected:
            apply(.connectionDropped)
            if case .reconnecting = state.broadcast {
                beginReconnectAttempt()
            }
        case .failed(let error):
            if case .reconnecting = state.broadcast {
                apply(.reconnectAttemptFailed)
            } else {
                apply(.failed(error))
            }
        case .statistics(let statistics):
            state.statistics = statistics
            publish()
        }
    }

    /// Exactly one attempt, with no backoff and no counter. The deadline that bounds
    /// it belongs to `syncDeadline()` rather than to this task, because a connection
    /// that returns without the destination ever confirming the publish must still
    /// time out.
    private func beginReconnectAttempt() {
        cancelReconnect()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            await self.broadcaster.stop()
            guard !Task.isCancelled, case .reconnecting = self.state.broadcast else { return }
            do {
                try await self.broadcaster.start(to: self.credentials)
            } catch {
                guard !Task.isCancelled else { return }
                if case .reconnecting = self.state.broadcast {
                    self.apply(.reconnectAttemptFailed)
                }
            }
        }
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    /// The RTMP layer's own bounds are looser than this screen needs: its socket waits
    /// 15 seconds to connect and each command 3 seconds more, which together outlast
    /// the 10 seconds a first connection is given here. Nothing bounds the wait for the
    /// destination to confirm a publish at all. Both waiting states are therefore
    /// bounded here — Connecting by `connectDeadline`, Reconnecting by
    /// `reconnectDeadline`.
    private func syncDeadline() {
        switch state.broadcast {
        case .connecting:
            startDeadline(connectDeadline, timingOutWith: .failed(.connectionTimedOut))
        case .reconnecting:
            startDeadline(reconnectDeadline, timingOutWith: .reconnectTimedOut)
        case .offline, .online, .failed:
            cancelDeadline()
        }
    }

    private func startDeadline(_ duration: Duration, timingOutWith event: BroadcastState.Event) {
        guard deadlineTask == nil else { return }
        let bounded = state.broadcast
        deadlineTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.state.broadcast == bounded else { return }
            self.apply(event)
            await self.broadcaster.stop()
        }
    }

    private func cancelDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
    }

    private func apply(_ event: BroadcastState.Event) {
        state.broadcast = state.broadcast.applying(event, at: clock.now)
        syncElapsedTime()
        syncDeadline()
        publish()
    }

    private func syncElapsedTime() {
        switch state.broadcast {
        case .online, .reconnecting:
            state.elapsedTimeText = elapsedText()
            startTickerIfNeeded()
        case .offline, .connecting, .failed:
            stopTicker()
            state.elapsedTimeText = ""
            if case .offline = state.broadcast {
                state.statistics = nil
            }
            if case .connecting = state.broadcast {
                state.statistics = nil
            }
        }
    }

    private func elapsedText(now: ContinuousClock.Instant? = nil) -> String {
        switch state.broadcast {
        case .online(let startedAt), .reconnecting(let startedAt):
            ElapsedTime.formatted(from: startedAt, to: now ?? clock.now)
        case .offline, .connecting, .failed:
            ""
        }
    }

    private func startTickerIfNeeded() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                switch self.state.broadcast {
                case .online, .reconnecting:
                    self.state.elapsedTimeText = self.elapsedText()
                    self.publish()
                default:
                    return
                }
            }
        }
    }

    private func stopTicker() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func publish() {
        continuation.yield(state)
    }
}
