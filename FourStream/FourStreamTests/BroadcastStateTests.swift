import Testing
@testable import FourStream

struct BroadcastStateTests {
    private let now = ContinuousClock().now

    @Test
    func failureFromOfflineEntersFailed() {
        let next = BroadcastState.offline.applying(.failed(.cameraAccessDenied), at: now)
        #expect(next == .failed(.cameraAccessDenied))
    }

    @Test
    func startFromOfflineEntersConnecting() {
        let next = BroadcastState.offline.applying(.startRequested, at: now)
        #expect(next == .connecting)
    }

    @Test
    func doubleStartFromConnectingIsIgnored() {
        let next = BroadcastState.connecting.applying(.startRequested, at: now)
        #expect(next == .connecting)
    }

    @Test
    func doubleStartFromOnlineIsIgnored() {
        let live = BroadcastState.online(startedAt: now)
        #expect(live.applying(.startRequested, at: now) == live)
    }

    @Test
    func doubleStartFromReconnectingIsIgnored() {
        let reconnecting = BroadcastState.reconnecting(startedAt: now)
        #expect(reconnecting.applying(.startRequested, at: now) == reconnecting)
    }

    @Test
    func failedDoesNotLeaveOnPublishingOrDrop() {
        let failed = BroadcastState.failed(.noNetwork)
        #expect(failed.applying(.publishingConfirmed, at: now) == failed)
        #expect(failed.applying(.connectionDropped, at: now) == failed)
        #expect(failed.applying(.reconnectTimedOut, at: now) == failed)
        #expect(failed.applying(.stopRequested, at: now) == failed)
    }

    @Test
    func failedLeavesOnlyOnRetryOrDismiss() {
        let failed = BroadcastState.failed(.noNetwork)
        #expect(failed.applying(.startRequested, at: now) == .connecting)
        #expect(failed.applying(.dismissed, at: now) == .offline)
    }

    @Test
    func firstConnectionFailureGoesToFailedNotReconnecting() {
        let next = BroadcastState.connecting.applying(.failed(.destinationRejected(detail: "x")), at: now)
        #expect(next == .failed(.destinationRejected(detail: "x")))
        #expect(BroadcastState.connecting.applying(.connectionDropped, at: now) == .connecting)
    }

    @Test
    func dropFromOnlineEntersReconnectingOnce() {
        let startedAt = now
        let online = BroadcastState.online(startedAt: startedAt)
        let reconnecting = online.applying(.connectionDropped, at: now)
        #expect(reconnecting == .reconnecting(startedAt: startedAt))
        #expect(reconnecting.applying(.connectionDropped, at: now) == reconnecting)
    }

    @Test
    func reconnectFailureAndTimeoutEnterFailedWithConnectionLost() {
        let reconnecting = BroadcastState.reconnecting(startedAt: now)
        #expect(reconnecting.applying(.reconnectAttemptFailed, at: now) == .failed(.connectionLost))
        #expect(reconnecting.applying(.reconnectTimedOut, at: now) == .failed(.connectionLost))
    }

    @Test
    func elapsedStartSurvivesDropAndSuccessfulReconnect() {
        let startedAt = now
        let recovered = BroadcastState.online(startedAt: startedAt)
            .applying(.connectionDropped, at: now)
            .applying(.publishingConfirmed, at: ContinuousClock().now)

        guard case .online(let recoveredStart) = recovered else {
            Issue.record("expected online, got \(recovered)")
            return
        }
        #expect(recoveredStart == startedAt)
    }

    @Test
    func elapsedStartResetsWhenReturningToOfflineOrFailed() {
        let startedAt = now
        let online = BroadcastState.online(startedAt: startedAt)
        #expect(online.applying(.stopRequested, at: now) == .offline)

        let afterDrop = online.applying(.connectionDropped, at: now)
        #expect(afterDrop.applying(.reconnectTimedOut, at: now) == .failed(.connectionLost))
    }
}
