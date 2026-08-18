enum BroadcastError: Error, Equatable, Sendable {
    case cameraAccessDenied
    case cameraAccessRestricted
    case microphoneAccessDenied
    case noCameraAvailable
    case cameraUnavailable
    case unsupportedQuality(reason: String)
    case noNetwork
    case destinationRejected(detail: String)
    case connectionTimedOut
    case connectionLost
    case audioSessionInterrupted

    var message: String {
        switch self {
        case .cameraAccessDenied:
            "FourStream needs camera access to broadcast."
        case .cameraAccessRestricted:
            "Camera access is blocked on this device."
        case .microphoneAccessDenied:
            "Your broadcast will have no sound without microphone access."
        case .noCameraAvailable:
            "No camera is available on this device."
        case .cameraUnavailable:
            "The camera stopped working. Close anything else using it and try again."
        case .unsupportedQuality(let reason):
            reason
        case .noNetwork:
            "No network connection."
        case .destinationRejected:
            "The streaming service rejected the broadcast. Check the address and stream key."
        case .connectionTimedOut:
            "The broadcast could not start in time. Check your connection and try again."
        case .connectionLost:
            "Stream connection lost."
        case .audioSessionInterrupted:
            "Your broadcast was interrupted by another app."
        }
    }

    var offeredAction: OfferedAction {
        switch self {
        case .cameraAccessDenied, .microphoneAccessDenied:
            .openSettings
        case .noNetwork, .destinationRejected, .connectionTimedOut, .connectionLost,
             .audioSessionInterrupted, .noCameraAvailable, .cameraUnavailable:
            .retry
        case .cameraAccessRestricted, .unsupportedQuality:
            .none
        }
    }
}

enum OfferedAction: Equatable, Sendable {
    case openSettings
    case retry
    case none
}
