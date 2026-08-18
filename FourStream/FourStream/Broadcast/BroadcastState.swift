enum BroadcastState: Equatable, Sendable {
    case offline
    case connecting
    case online(startedAt: ContinuousClock.Instant)
    case reconnecting(startedAt: ContinuousClock.Instant)
    case failed(BroadcastError)

    enum Event: Equatable, Sendable {
        case startRequested
        case publishingConfirmed
        case failed(BroadcastError)
        case stopRequested
        case connectionDropped
        case reconnectAttemptFailed
        case reconnectTimedOut
        case dismissed
        case leftForeground
        case confirmedLeavingScreen
    }

    func applying(_ event: Event, at now: ContinuousClock.Instant) -> BroadcastState {
        switch event {
        case .leftForeground, .confirmedLeavingScreen:
            return .offline
        case .startRequested:
            switch self {
            case .offline, .failed:
                return .connecting
            case .connecting, .online, .reconnecting:
                return self
            }
        case .publishingConfirmed:
            switch self {
            case .connecting:
                return .online(startedAt: now)
            case .reconnecting(let startedAt):
                return .online(startedAt: startedAt)
            case .offline, .online, .failed:
                return self
            }
        case .failed(let error):
            return .failed(error)
        case .stopRequested:
            switch self {
            case .connecting, .online, .reconnecting:
                return .offline
            case .offline, .failed:
                return self
            }
        case .connectionDropped:
            switch self {
            case .online(let startedAt):
                return .reconnecting(startedAt: startedAt)
            case .offline, .connecting, .reconnecting, .failed:
                return self
            }
        case .reconnectAttemptFailed, .reconnectTimedOut:
            switch self {
            case .reconnecting:
                return .failed(.connectionLost)
            case .offline, .connecting, .online, .failed:
                return self
            }
        case .dismissed:
            switch self {
            case .failed:
                return .offline
            case .offline, .connecting, .online, .reconnecting:
                return self
            }
        }
    }
}
