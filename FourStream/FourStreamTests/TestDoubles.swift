import Foundation
@testable import FourStream

/// A `Broadcasting` that records what it was asked to do and emits whatever events
/// a test scripts, so the broadcasting screen's behaviour can be exercised without
/// a camera or an RTMP server.
actor BroadcastingDouble: Broadcasting {
    enum Operation: Equatable {
        case prepare
        case start
        case stop
        case teardown
    }

    enum Failure: Error {
        case unknown
    }

    let events: AsyncStream<BroadcastEvent>

    var prepareError: (any Error)?
    var startError: BroadcastError?
    var configuration = CaptureConfiguration(
        cameraPosition: .back,
        isMicrophoneEnabled: false,
        availableCameraPositions: [.front, .back]
    )

    /// Every call in the order it happened, so a test can assert that releasing and
    /// preparing capture never overlap.
    private(set) var operations: [Operation] = []

    /// Makes releasing capture slow enough that a preparation asked for at the same
    /// moment would interleave with it if nothing serialised the two.
    var teardownDelay: Duration?

    private(set) var prepareCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var teardownCount = 0
    private(set) var attachedPreviewCount = 0
    private(set) var microphoneSettings: [Bool] = []

    private let continuation: AsyncStream<BroadcastEvent>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: BroadcastEvent.self)
        events = stream
        self.continuation = continuation
    }

    func emit(_ event: BroadcastEvent) {
        continuation.yield(event)
    }

    func setPrepareError(_ error: (any Error)?) {
        prepareError = error
    }

    func setTeardownDelay(_ delay: Duration?) {
        teardownDelay = delay
    }

    func setStartError(_ error: BroadcastError?) {
        startError = error
    }

    func setAvailableCameraPositions(_ positions: Set<CameraPosition>) {
        configuration.availableCameraPositions = positions
    }

    func prepare(quality: StreamQuality) async throws {
        prepareCount += 1
        operations.append(.prepare)
        if let prepareError {
            throw prepareError
        }
    }

    func attachPreview(_ surface: PreviewSurface) async {
        attachedPreviewCount += 1
    }

    func start(to credentials: StreamCredentials) async throws {
        startCount += 1
        operations.append(.start)
        if let startError {
            throw startError
        }
    }

    func stop() async {
        stopCount += 1
        operations.append(.stop)
    }

    func captureConfiguration() -> CaptureConfiguration {
        configuration
    }

    func switchCamera(to position: CameraPosition) async throws {
        guard configuration.availableCameraPositions.contains(position) else {
            throw BroadcastError.noCameraAvailable
        }
        configuration.cameraPosition = position
    }

    func setMicrophoneEnabled(_ enabled: Bool) async {
        microphoneSettings.append(enabled)
        configuration.isMicrophoneEnabled = enabled
    }

    func teardown() async {
        teardownCount += 1
        if let teardownDelay {
            try? await Task.sleep(for: teardownDelay)
        }
        operations.append(.teardown)
        configuration.isMicrophoneEnabled = false
    }
}

/// A `MediaAuthorizing` with scripted answers that records every request, which is
/// what makes the just-in-time permission rule assertable.
///
/// The unchecked conformance is sound for these tests: the view model reads and
/// requests only from the main actor, and the tests drive it from there too.
final class MediaAuthorizerDouble: MediaAuthorizing, @unchecked Sendable {
    var cameraStatus: AuthorizationStatus
    var microphoneStatus: AuthorizationStatus

    /// What an undecided permission becomes when asked, standing in for the answer
    /// the user gives at the system prompt. An already decided one does not change.
    var cameraAnswer: AuthorizationStatus = .granted
    var microphoneAnswer: AuthorizationStatus = .granted

    private(set) var requests: [MediaKind] = []

    init(camera: AuthorizationStatus = .granted, microphone: AuthorizationStatus = .granted) {
        cameraStatus = camera
        microphoneStatus = microphone
    }

    func status(for media: MediaKind) -> AuthorizationStatus {
        switch media {
        case .camera: cameraStatus
        case .microphone: microphoneStatus
        }
    }

    func requestAccess(to media: MediaKind) async -> AuthorizationStatus {
        requests.append(media)
        switch media {
        case .camera:
            if cameraStatus == .notDetermined {
                cameraStatus = cameraAnswer
            }
            return cameraStatus
        case .microphone:
            if microphoneStatus == .notDetermined {
                microphoneStatus = microphoneAnswer
            }
            return microphoneStatus
        }
    }
}

/// An in-memory `CredentialsStoring`, so the configuration flow can be tested
/// without touching the real Keychain.
final class CredentialsStoreDouble: CredentialsStoring, @unchecked Sendable {
    enum Failure: Error {
        case unavailable
    }

    var stored: StreamCredentials?
    var loadError: Failure?
    var saveError: Failure?
    private(set) var saveCount = 0

    init(stored: StreamCredentials? = nil) {
        self.stored = stored
    }

    func load() throws -> StreamCredentials? {
        if let loadError {
            throw loadError
        }
        return stored
    }

    func save(_ credentials: StreamCredentials) throws {
        if let saveError {
            throw saveError
        }
        stored = credentials
        saveCount += 1
    }

    func delete() throws {
        stored = nil
    }
}

extension StreamCredentials {
    static func stub(
        address: String = "rtmp://live.example.com/app",
        streamKey: String = "live_secret_key_value"
    ) -> StreamCredentials {
        StreamCredentials(ingestURL: URL(string: address)!, streamKey: streamKey)
    }
}
