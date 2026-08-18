import CoreGraphics

nonisolated enum CameraPosition: Equatable, Hashable, Sendable {
    case front
    case back
}

nonisolated struct CaptureConfiguration: Equatable, Sendable {
    var cameraPosition: CameraPosition
    var isMicrophoneEnabled: Bool
    var availableCameraPositions: Set<CameraPosition>

    var canSwitchCamera: Bool {
        availableCameraPositions.count > 1
    }

    /// An empty set means capture has not reported yet — between broadcasts, or
    /// before the screen has prepared — which is not a statement about the device.
    /// A device that genuinely has no camera is reported as a failure instead.
    var cameraSwitchUnavailableReason: String? {
        guard !canSwitchCamera, !availableCameraPositions.isEmpty else {
            return nil
        }
        return "This device has only one camera."
    }
}

nonisolated struct StreamStatistics: Equatable, Sendable {
    var videoBitrate: Int
    var audioBitrate: Int
    var resolution: CGSize
    var frameRate: Int
    var videoCodec: VideoCodec
    var audioCodec: AudioCodec
}

/// What the streaming boundary reports upward. There is deliberately no event for
/// "connecting": the screen enters that state when the user asks for a broadcast,
/// and an event that could also enter it would let a connection nobody is waiting
/// for put the screen back on air.
enum BroadcastEvent: Equatable, Sendable {
    case publishing
    case disconnected
    case failed(BroadcastError)
    case statistics(StreamStatistics)
}

struct PreviewSurface: @unchecked Sendable {
    let view: AnyObject
}

protocol Broadcasting: Actor {
    var events: AsyncStream<BroadcastEvent> { get }

    func prepare(quality: StreamQuality) async throws
    func attachPreview(_ surface: PreviewSurface) async
    func start(to credentials: StreamCredentials) async throws
    func stop() async
    func captureConfiguration() -> CaptureConfiguration
    func switchCamera(to position: CameraPosition) async throws
    func setMicrophoneEnabled(_ enabled: Bool) async
    func teardown() async
}
