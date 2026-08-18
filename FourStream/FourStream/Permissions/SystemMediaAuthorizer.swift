import AVFoundation

struct SystemMediaAuthorizer: MediaAuthorizing {
    func status(for media: MediaKind) -> AuthorizationStatus {
        mapped(AVCaptureDevice.authorizationStatus(for: Self.captureType(media)))
    }

    func requestAccess(to media: MediaKind) async -> AuthorizationStatus {
        let granted = await AVCaptureDevice.requestAccess(for: Self.captureType(media))
        if granted {
            return .granted
        }
        return status(for: media)
    }

    private static func captureType(_ media: MediaKind) -> AVMediaType {
        switch media {
        case .camera: .video
        case .microphone: .audio
        }
    }

    private func mapped(_ status: AVAuthorizationStatus) -> AuthorizationStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }
}
