import Foundation

enum ElapsedTime {
    static func formatted(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> String {
        formatted(duration: end - start)
    }

    static func formatted(duration: Duration) -> String {
        let totalSeconds = max(0, duration.components.seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours >= 1 {
            return String(format: "%02lld:%02lld:%02lld", hours, minutes, seconds)
        }
        return String(format: "%02lld:%02lld", minutes, seconds)
    }
}
