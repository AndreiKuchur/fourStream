enum MediaKind: Equatable, Sendable {
    case camera
    case microphone
}

enum AuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

protocol MediaAuthorizing: Sendable {
    func status(for media: MediaKind) -> AuthorizationStatus
    func requestAccess(to media: MediaKind) async -> AuthorizationStatus
}
