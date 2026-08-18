import Testing
@testable import FourStream

struct BroadcastErrorTests {
    private let streamKey = "live_secret_key_value"

    @Test
    func everyCaseHasAPlainLanguageMessageThatNamesTheFailure() {
        for error in Self.allCases {
            let message = error.message
            #expect(!message.isEmpty)
            #expect(message.hasSuffix("."))
            #expect(!containsTechnicalJargon(message))
            #expect(namesWhatWentWrong(error))
        }
    }

    @Test
    func messagesNeverContainTheStreamKey() {
        let errorsWithAssociatedValues: [BroadcastError] = [
            .unsupportedQuality(reason: "This camera cannot record at 720p."),
            .destinationRejected(detail: streamKey),
        ]

        for error in Self.allCases + errorsWithAssociatedValues {
            #expect(!error.message.contains(streamKey))
        }
    }

    @Test
    func destinationRejectionDoesNotSurfaceTheServerDetail() {
        let error = BroadcastError.destinationRejected(detail: streamKey)
        #expect(error.message == "The streaming service rejected the broadcast. Check the address and stream key.")
        #expect(!error.message.contains(streamKey))
    }

    @Test
    func offeredActionMatchesWhatTheUserCanDo() {
        #expect(BroadcastError.cameraAccessDenied.offeredAction == .openSettings)
        #expect(BroadcastError.cameraAccessRestricted.offeredAction == .none)
        #expect(BroadcastError.microphoneAccessDenied.offeredAction == .openSettings)
        #expect(BroadcastError.noCameraAvailable.offeredAction == .retry)
        #expect(BroadcastError.cameraUnavailable.offeredAction == .retry)
        #expect(BroadcastError.unsupportedQuality(reason: "This camera cannot record at 720p.").offeredAction == .none)
        #expect(BroadcastError.noNetwork.offeredAction == .retry)
        #expect(BroadcastError.destinationRejected(detail: streamKey).offeredAction == .retry)
        #expect(BroadcastError.connectionTimedOut.offeredAction == .retry)
        #expect(BroadcastError.connectionLost.offeredAction == .retry)
        #expect(BroadcastError.audioSessionInterrupted.offeredAction == .retry)
    }

    private static let allCases: [BroadcastError] = [
        .cameraAccessDenied,
        .cameraAccessRestricted,
        .microphoneAccessDenied,
        .noCameraAvailable,
        .cameraUnavailable,
        .unsupportedQuality(reason: "This camera cannot record at 720p."),
        .noNetwork,
        .destinationRejected(detail: "live_secret_key_value"),
        .connectionTimedOut,
        .connectionLost,
        .audioSessionInterrupted,
    ]

    private func containsTechnicalJargon(_ message: String) -> Bool {
        let forbidden = ["NSError", "OSStatus", "RTMP", "HTTP", "code ", "domain", "stack"]
        return forbidden.contains { message.lowercased().contains($0.lowercased()) }
    }

    private func namesWhatWentWrong(_ error: BroadcastError) -> Bool {
        switch error {
        case .cameraAccessDenied, .cameraAccessRestricted:
            error.message.lowercased().contains("camera")
        case .microphoneAccessDenied:
            error.message.lowercased().contains("microphone")
                || error.message.lowercased().contains("sound")
        case .noCameraAvailable, .cameraUnavailable:
            error.message.lowercased().contains("camera")
        case .unsupportedQuality(let reason):
            error.message == reason && !reason.isEmpty
        case .noNetwork:
            error.message.lowercased().contains("network")
        case .destinationRejected:
            error.message.lowercased().contains("rejected")
        case .connectionTimedOut:
            error.message.lowercased().contains("in time")
        case .connectionLost:
            error.message.lowercased().contains("lost")
        case .audioSessionInterrupted:
            error.message.lowercased().contains("interrupted")
        }
    }
}
