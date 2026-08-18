import Foundation
import Testing
@testable import FourStream

@MainActor
struct BroadcastViewModelTests {

    // MARK: - Permission timing

    @Test
    func reachingTheScreenAsksForTheCameraAndNothingElse() async {
        let broadcaster = BroadcastingDouble()
        let authorizer = MediaAuthorizerDouble(camera: .granted, microphone: .notDetermined)
        let viewModel = makeViewModel(broadcaster: broadcaster, authorizer: authorizer)

        await viewModel.appear(preview: Self.preview)

        #expect(authorizer.requests == [.camera])
        let prepared = await broadcaster.prepareCount
        #expect(prepared == 1)
        #expect(viewModel.state.broadcast == .offline)
        #expect(viewModel.state.capture.isMicrophoneEnabled)
    }

    @Test
    func pressingStartAsksForMicrophoneAccessAtThatMoment() async {
        let broadcaster = BroadcastingDouble()
        let authorizer = MediaAuthorizerDouble(camera: .granted, microphone: .notDetermined)
        let viewModel = makeViewModel(broadcaster: broadcaster, authorizer: authorizer)
        await viewModel.appear(preview: Self.preview)

        await viewModel.start()

        #expect(authorizer.requests == [.camera, .microphone])
        #expect(viewModel.state.capture.isMicrophoneEnabled)
        let microphoneSettings = await broadcaster.microphoneSettings
        #expect(microphoneSettings.last == true)
    }

    @Test
    func turningTheMicrophoneBackOnAsksForAccessAtThatMoment() async {
        let broadcaster = BroadcastingDouble()
        let authorizer = MediaAuthorizerDouble(camera: .granted, microphone: .notDetermined)
        let viewModel = makeViewModel(broadcaster: broadcaster, authorizer: authorizer)
        await viewModel.appear(preview: Self.preview)

        await viewModel.toggleMicrophone()
        #expect(authorizer.requests == [.camera])
        #expect(!viewModel.state.capture.isMicrophoneEnabled)

        await viewModel.toggleMicrophone()

        #expect(authorizer.requests == [.camera, .microphone])
        #expect(viewModel.state.capture.isMicrophoneEnabled)
    }

    @Test
    func silencingTheMicrophoneBeforeStartKeepsItUnaskedAndTheBroadcastSilent() async {
        let broadcaster = BroadcastingDouble()
        let authorizer = MediaAuthorizerDouble(camera: .granted, microphone: .notDetermined)
        let viewModel = makeViewModel(broadcaster: broadcaster, authorizer: authorizer)
        await viewModel.appear(preview: Self.preview)
        await viewModel.toggleMicrophone()

        await viewModel.start()

        #expect(authorizer.requests == [.camera])
        #expect(!viewModel.state.capture.isMicrophoneEnabled)
        let microphoneSettings = await broadcaster.microphoneSettings
        #expect(microphoneSettings.last == false)
    }

    @Test
    func refusingTheMicrophonePromptStillStartsTheBroadcast() async {
        let broadcaster = BroadcastingDouble()
        let authorizer = MediaAuthorizerDouble(camera: .granted, microphone: .notDetermined)
        authorizer.microphoneAnswer = .denied
        let viewModel = makeViewModel(broadcaster: broadcaster, authorizer: authorizer)
        await viewModel.appear(preview: Self.preview)

        await viewModel.start()

        #expect(authorizer.requests == [.camera, .microphone])
        #expect(viewModel.state.broadcast == .connecting)
        let started = await broadcaster.startCount
        #expect(started == 1)
        #expect(!viewModel.state.capture.isMicrophoneEnabled)
        #expect(viewModel.isMicrophoneSilencedByAccess)
        #expect(viewModel.canOpenSystemSettings)
    }

    @Test
    func aRefusedMicrophoneIsNotAskedForAgainAndTheControlStaysOff() async {
        let broadcaster = BroadcastingDouble()
        let authorizer = MediaAuthorizerDouble(camera: .granted, microphone: .denied)
        let viewModel = makeViewModel(broadcaster: broadcaster, authorizer: authorizer)
        await viewModel.appear(preview: Self.preview)

        await viewModel.toggleMicrophone()

        #expect(authorizer.requests == [.camera])
        #expect(!viewModel.state.capture.isMicrophoneEnabled)
        #expect(viewModel.isMicrophoneSilencedByAccess)
    }

    // MARK: - Refused and restricted access

    @Test
    func refusedCameraAccessExplainsItselfAndOffersSettings() async {
        let broadcaster = BroadcastingDouble()
        let viewModel = makeViewModel(broadcaster: broadcaster, camera: .denied)

        await viewModel.appear(preview: Self.preview)

        #expect(viewModel.state.broadcast == .failed(.cameraAccessDenied))
        #expect(viewModel.canOpenSystemSettings)
        #expect(viewModel.isPreviewObscured)
        let prepared = await broadcaster.prepareCount
        #expect(prepared == 0)
    }

    @Test
    func restrictedCameraAccessOffersNoSettingsRoute() async {
        let viewModel = makeViewModel(camera: .restricted)

        await viewModel.appear(preview: Self.preview)

        #expect(viewModel.state.broadcast == .failed(.cameraAccessRestricted))
        #expect(!viewModel.canOpenSystemSettings)
    }

    @Test
    func previewRecoversWhenAccessIsGrantedAfterARefusal() async {
        let broadcaster = BroadcastingDouble()
        let authorizer = MediaAuthorizerDouble(camera: .denied, microphone: .notDetermined)
        let viewModel = makeViewModel(broadcaster: broadcaster, authorizer: authorizer)
        await viewModel.appear(preview: Self.preview)
        #expect(viewModel.state.broadcast == .failed(.cameraAccessDenied))

        authorizer.cameraStatus = .granted
        await viewModel.didBecomeActive()

        #expect(viewModel.state.broadcast == .offline)
        let prepared = await broadcaster.prepareCount
        #expect(prepared == 1)
    }

    // MARK: - Starting and stopping

    @Test
    func aSecondStartDuringPreparationIsRefused() async {
        let broadcaster = BroadcastingDouble()
        let viewModel = makeViewModel(broadcaster: broadcaster)

        async let first: Void = viewModel.start()
        async let second: Void = viewModel.start()
        _ = await (first, second)

        let started = await broadcaster.startCount
        #expect(started == 1)
        #expect(viewModel.state.broadcast == .connecting)
    }

    @Test
    func anUnsupportedConfigurationIsRefusedBeforeConnecting() async {
        let broadcaster = BroadcastingDouble()
        await broadcaster.setPrepareError(
            BroadcastError.unsupportedQuality(reason: "Frame rate not available: 30 fps.")
        )
        let viewModel = makeViewModel(broadcaster: broadcaster)

        await viewModel.start()

        #expect(
            viewModel.state.broadcast
                == .failed(.unsupportedQuality(reason: "Frame rate not available: 30 fps."))
        )
        let started = await broadcaster.startCount
        #expect(started == 0)
    }

    @Test
    func aBroadcastStartsSilentWhenTheMicrophoneWasRefused() async {
        let broadcaster = BroadcastingDouble()
        let authorizer = MediaAuthorizerDouble(camera: .granted, microphone: .denied)
        let viewModel = makeViewModel(broadcaster: broadcaster, authorizer: authorizer)
        await viewModel.appear(preview: Self.preview)

        await viewModel.start()

        #expect(viewModel.state.broadcast == .connecting)
        let started = await broadcaster.startCount
        #expect(started == 1)
        #expect(!viewModel.state.capture.isMicrophoneEnabled)
        #expect(viewModel.isMicrophoneSilencedByAccess)
        #expect(authorizer.requests == [.camera])
    }

    @Test
    func stoppingWhileConnectingReturnsToOffline() async {
        let broadcaster = BroadcastingDouble()
        let viewModel = makeViewModel(broadcaster: broadcaster)
        await viewModel.appear(preview: Self.preview)
        await viewModel.start()

        await viewModel.stop()

        #expect(viewModel.state.broadcast == .offline)
        let stopped = await broadcaster.stopCount
        #expect(stopped == 1)
    }

    // MARK: - State and elapsed time

    @Test
    func publishingConfirmationMovesToOnlineAndShowsElapsedTime() async {
        let broadcaster = BroadcastingDouble()
        let viewModel = makeViewModel(broadcaster: broadcaster)
        await viewModel.appear(preview: Self.preview)
        await viewModel.start()

        await broadcaster.emit(.publishing)

        #expect(await wait(for: viewModel, until: Self.isOnline))
        #expect(viewModel.state.elapsedTimeText == "00:00")
        #expect(viewModel.isStatusTappable)
        #expect(!viewModel.isPreviewObscured)
    }

    @Test
    func theStatusPanelIsNotTappableOutsideOnline() async {
        let viewModel = makeViewModel(camera: .denied)
        #expect(!viewModel.isStatusTappable)

        await viewModel.appear(preview: Self.preview)

        #expect(!viewModel.isStatusTappable)
    }

    @Test
    func anErrorStaysUntilTheUserDismissesIt() async {
        let viewModel = makeViewModel(camera: .denied)
        await viewModel.appear(preview: Self.preview)
        #expect(viewModel.failure == .cameraAccessDenied)

        viewModel.dismissFailure()

        #expect(viewModel.state.broadcast == .offline)
        #expect(viewModel.failure == nil)
    }

    @Test
    func aCameraLostDuringTheSessionIsReportedAndRebuiltOnRetry() async {
        let broadcaster = BroadcastingDouble()
        let viewModel = makeViewModel(broadcaster: broadcaster)
        await viewModel.appear(preview: Self.preview)

        await broadcaster.emit(.failed(.cameraUnavailable))

        #expect(await wait(for: viewModel) { $0.broadcast == .failed(.cameraUnavailable) })
        #expect(viewModel.isPreviewObscured)
        #expect(viewModel.failure?.offeredAction == .retry)

        await viewModel.retryFailure()

        #expect(viewModel.state.broadcast == .offline)
        let released = await broadcaster.teardownCount
        #expect(released == 1)
        let prepared = await broadcaster.prepareCount
        #expect(prepared == 2)
    }

    @Test
    func aCaptureFailureTheBoundaryDoesNotNameIsNotBlamedOnMissingHardware() async {
        let broadcaster = BroadcastingDouble()
        await broadcaster.setPrepareError(BroadcastingDouble.Failure.unknown)
        let viewModel = makeViewModel(broadcaster: broadcaster)

        await viewModel.appear(preview: Self.preview)

        #expect(viewModel.state.broadcast == .failed(.cameraUnavailable))
        #expect(viewModel.failure?.offeredAction == .retry)
    }

    @Test
    func nothingIsClaimedAboutCamerasBeforeCaptureHasReportedAny() {
        let unknown = CaptureConfiguration(
            cameraPosition: .back,
            isMicrophoneEnabled: false,
            availableCameraPositions: []
        )

        #expect(unknown.cameraSwitchUnavailableReason == nil)
        #expect(!unknown.canSwitchCamera)
    }

    // MARK: - Background and foreground

    @Test
    func returningToTheForegroundRebuildsThePreviewOnlyAfterTheReleaseHasFinished() async {
        let broadcaster = BroadcastingDouble()
        await broadcaster.setTeardownDelay(.milliseconds(30))
        let viewModel = makeViewModel(broadcaster: broadcaster)
        await viewModel.appear(preview: Self.preview)
        await viewModel.start()
        await broadcaster.emit(.publishing)
        #expect(await wait(for: viewModel, until: Self.isOnline))

        async let left: Void = viewModel.didLeaveForeground()
        async let returned: Void = viewModel.didBecomeActive()
        _ = await (left, returned)

        #expect(viewModel.state.broadcast == .offline)
        let operations = await broadcaster.operations
        #expect(operations.filter { $0 == .teardown || $0 == .prepare } == [.prepare, .teardown, .prepare])
    }

    @Test
    func aConnectionThatOutlivedTheBroadcastCannotPutTheScreenBackOnline() async {
        let broadcaster = BroadcastingDouble()
        let viewModel = makeViewModel(broadcaster: broadcaster)
        await viewModel.appear(preview: Self.preview)
        await viewModel.start()
        await broadcaster.emit(.publishing)
        #expect(await wait(for: viewModel, until: Self.isOnline))
        await viewModel.didLeaveForeground()

        await broadcaster.emit(.publishing)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.state.broadcast == .offline)
        #expect(viewModel.state.elapsedTimeText.isEmpty)
    }

    @Test
    func returningToTheForegroundLeavesAConnectionFailureOnScreen() async {
        let broadcaster = BroadcastingDouble()
        let viewModel = makeViewModel(broadcaster: broadcaster)
        await viewModel.appear(preview: Self.preview)
        await broadcaster.emit(.failed(.destinationRejected(detail: "")))
        #expect(await wait(for: viewModel) { $0.broadcast == .failed(.destinationRejected(detail: "")) })

        await viewModel.didBecomeActive()

        #expect(viewModel.state.broadcast == .failed(.destinationRejected(detail: "")))
    }

    // MARK: - Reconnection

    @Test
    func aDropMakesExactlyOneReconnectionAttemptAndKeepsTheClockRunning() async {
        let broadcaster = BroadcastingDouble()
        let viewModel = makeViewModel(broadcaster: broadcaster)
        await viewModel.appear(preview: Self.preview)
        await viewModel.start()
        await broadcaster.emit(.publishing)
        #expect(await wait(for: viewModel, until: Self.isOnline))

        await broadcaster.emit(.disconnected)

        #expect(await wait(for: viewModel, until: Self.isReconnecting))
        #expect(await waitForStartCount(2, on: broadcaster))
        #expect(viewModel.isPreviewObscured)
        #expect(!viewModel.state.elapsedTimeText.isEmpty)

        let attemptsAfterSettling = await broadcaster.startCount
        #expect(attemptsAfterSettling == 2)

        await viewModel.disappear()
    }

    @Test
    func aFailedReconnectionAttemptEndsInErrorOfferingARetry() async {
        let broadcaster = BroadcastingDouble()
        let viewModel = makeViewModel(broadcaster: broadcaster)
        await viewModel.appear(preview: Self.preview)
        await viewModel.start()
        await broadcaster.emit(.publishing)
        #expect(await wait(for: viewModel, until: Self.isOnline))
        await broadcaster.setStartError(.noNetwork)

        await broadcaster.emit(.disconnected)

        #expect(await wait(for: viewModel) { $0.broadcast == .failed(.connectionLost) })
        #expect(viewModel.failure?.offeredAction == .retry)
        #expect(viewModel.isPreviewObscured)
        #expect(viewModel.state.elapsedTimeText.isEmpty)
    }

    @Test
    func reconnectingResolvesIntoErrorWhenItsDeadlineExpires() async {
        let broadcaster = BroadcastingDouble()
        let viewModel = makeViewModel(
            broadcaster: broadcaster,
            reconnectDeadline: .milliseconds(50)
        )
        await viewModel.appear(preview: Self.preview)
        await viewModel.start()
        await broadcaster.emit(.publishing)
        #expect(await wait(for: viewModel, until: Self.isOnline))

        await broadcaster.emit(.disconnected)

        #expect(await wait(for: viewModel) { $0.broadcast == .failed(.connectionLost) })
    }

    // MARK: - Connection deadline

    @Test
    func connectingResolvesIntoAMessageWhenItsDeadlineExpires() async {
        let broadcaster = BroadcastingDouble()
        let viewModel = makeViewModel(
            broadcaster: broadcaster,
            connectDeadline: .milliseconds(50)
        )
        await viewModel.appear(preview: Self.preview)

        await viewModel.start()

        #expect(await wait(for: viewModel) { $0.broadcast == .failed(.connectionTimedOut) })
        #expect(viewModel.failure?.offeredAction == .retry)
        let stopped = await broadcaster.stopCount
        #expect(stopped >= 1)
    }

    @Test
    func reachingOnlineCancelsTheConnectionDeadline() async {
        let broadcaster = BroadcastingDouble()
        let viewModel = makeViewModel(
            broadcaster: broadcaster,
            connectDeadline: .milliseconds(50)
        )
        await viewModel.appear(preview: Self.preview)
        await viewModel.start()

        await broadcaster.emit(.publishing)
        #expect(await wait(for: viewModel, until: Self.isOnline))
        try? await Task.sleep(for: .milliseconds(120))

        #expect(Self.isOnline(viewModel.state))
    }

    // MARK: - Lifecycle

    @Test
    func leavingTheForegroundEndsTheBroadcastAndReleasesCapture() async {
        let broadcaster = BroadcastingDouble()
        let viewModel = makeViewModel(broadcaster: broadcaster)
        await viewModel.appear(preview: Self.preview)
        await viewModel.start()
        await broadcaster.emit(.publishing)
        #expect(await wait(for: viewModel, until: Self.isOnline))

        await viewModel.didLeaveForeground()

        #expect(viewModel.state.broadcast == .offline)
        #expect(viewModel.state.elapsedTimeText.isEmpty)
        let releases = await broadcaster.teardownCount
        #expect(releases == 1)
    }

    @Test
    func leavingTheScreenReleasesCaptureAndReportsNotBroadcasting() async {
        let broadcaster = BroadcastingDouble()
        let viewModel = makeViewModel(broadcaster: broadcaster)
        await viewModel.appear(preview: Self.preview)
        await viewModel.start()

        await viewModel.confirmLeaving()

        #expect(viewModel.state.broadcast == .offline)
        let releases = await broadcaster.teardownCount
        #expect(releases == 1)
    }

    // MARK: - Camera controls

    @Test
    func switchingIsUnavailableWithASingleCameraAndStatesWhy() async {
        let broadcaster = BroadcastingDouble()
        await broadcaster.setAvailableCameraPositions([.back])
        let viewModel = makeViewModel(broadcaster: broadcaster)

        await viewModel.appear(preview: Self.preview)
        await viewModel.switchCamera()

        #expect(!viewModel.state.capture.canSwitchCamera)
        #expect(viewModel.state.capture.cameraSwitchUnavailableReason == "This device has only one camera.")
        #expect(viewModel.state.capture.cameraPosition == .back)
    }

    @Test
    func switchingMovesToTheOtherCameraWhenBothExist() async {
        let broadcaster = BroadcastingDouble()
        let viewModel = makeViewModel(broadcaster: broadcaster)
        await viewModel.appear(preview: Self.preview)

        await viewModel.switchCamera()

        #expect(viewModel.state.capture.cameraPosition == .front)
        #expect(viewModel.state.capture.canSwitchCamera)
    }

    // MARK: - Helpers

    private static let preview = PreviewSurface(view: NSObject())

    private static func isOnline(_ state: BroadcastScreenState) -> Bool {
        if case .online = state.broadcast { true } else { false }
    }

    private static func isReconnecting(_ state: BroadcastScreenState) -> Bool {
        if case .reconnecting = state.broadcast { true } else { false }
    }

    private func makeViewModel(
        broadcaster: BroadcastingDouble = BroadcastingDouble(),
        authorizer: MediaAuthorizerDouble? = nil,
        camera: AuthorizationStatus = .granted,
        connectDeadline: Duration = .seconds(10),
        reconnectDeadline: Duration = .seconds(15)
    ) -> BroadcastViewModel {
        BroadcastViewModel(
            credentials: .stub(),
            broadcaster: broadcaster,
            mediaAuthorizer: authorizer ?? MediaAuthorizerDouble(camera: camera),
            connectDeadline: connectDeadline,
            reconnectDeadline: reconnectDeadline
        )
    }

    /// Broadcaster events reach the view model through a task of its own, so the
    /// assertions wait for the state to catch up rather than assuming it already has.
    private func wait(
        for viewModel: BroadcastViewModel,
        timeout: Duration = .seconds(2),
        until predicate: (BroadcastScreenState) -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if predicate(viewModel.state) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return predicate(viewModel.state)
    }

    private func waitForStartCount(
        _ expected: Int,
        on broadcaster: BroadcastingDouble,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await broadcaster.startCount == expected {
                return true
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return await broadcaster.startCount == expected
    }
}
