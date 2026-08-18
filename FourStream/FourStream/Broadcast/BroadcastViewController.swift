import UIKit

final class BroadcastViewController: UIViewController, UIGestureRecognizerDelegate, UIAdaptivePresentationControllerDelegate {
    private let viewModel: BroadcastViewModel
    private let previewContainer = PreviewContainerView()
    private let startStopButton = UIButton(type: .system)
    private let cameraButton = UIButton(type: .system)
    private let microphoneButton = UIButton(type: .system)
    private let cameraUnavailableLabel = UILabel()
    private let statusPanel = StatusPanelView()
    private let failureBanner = FailureBannerView()
    private var renderTask: Task<Void, Never>?
    private weak var previousPopGestureDelegate: (any UIGestureRecognizerDelegate)?
    private var isConfirmingLeave = false
    private weak var detailsController: StreamDetailsViewController?

    init(viewModel: BroadcastViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Broadcast"
        view.backgroundColor = .black
        navigationItem.largeTitleDisplayMode = .never
        installBackControl()
        configureViews()
        layoutViews()
        observeLifecycle()
        renderTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.viewModel.states {
                self.render(state)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        previousPopGestureDelegate = navigationController?.interactivePopGestureRecognizer?.delegate
        navigationController?.interactivePopGestureRecognizer?.delegate = self
        Task { await viewModel.appear(preview: PreviewSurface(view: previewContainer.previewView)) }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.delegate = previousPopGestureDelegate
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent {
            renderTask?.cancel()
            NotificationCenter.default.removeObserver(self)
            Task { await viewModel.disappear() }
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === navigationController?.interactivePopGestureRecognizer else {
            return true
        }
        if viewModel.needsLeaveConfirmation {
            presentLeaveConfirmation()
            return false
        }
        return true
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        detailsController = nil
    }

    private func render(_ state: BroadcastScreenState) {
        UIApplication.shared.isIdleTimerDisabled = viewModel.preventsAutoLock
        previewContainer.setObscured(viewModel.isPreviewObscured)
        statusPanel.render(
            stateText: statusText(for: state.broadcast),
            durationText: state.elapsedTimeText,
            isTappable: viewModel.isStatusTappable
        )
        renderFailureBanner(state)

        switch state.broadcast {
        case .offline, .failed:
            startStopButton.configuration?.title = "Start"
            startStopButton.isEnabled = true
        case .connecting:
            startStopButton.configuration?.title = "Stop"
            startStopButton.isEnabled = true
        case .online, .reconnecting:
            startStopButton.configuration?.title = "Stop"
            startStopButton.isEnabled = true
        }

        let capture = state.capture
        cameraButton.configuration?.title = capture.cameraPosition == .back ? "Back camera" : "Front camera"
        cameraButton.isEnabled = capture.canSwitchCamera
        cameraUnavailableLabel.text = capture.cameraSwitchUnavailableReason
        cameraUnavailableLabel.isHidden = capture.cameraSwitchUnavailableReason == nil
        microphoneButton.configuration?.title = microphoneTitle(for: state)
    }

    private func renderFailureBanner(_ state: BroadcastScreenState) {
        if let error = viewModel.failure {
            failureBanner.isHidden = false
            failureBanner.render(error: error)
        } else if viewModel.isMicrophoneSilencedByAccess {
            failureBanner.isHidden = false
            failureBanner.renderMicrophoneSilence(canOpenSettings: viewModel.canOpenSystemSettings)
        } else {
            failureBanner.isHidden = true
        }

        if let details = detailsController {
            let liveStatistics: StreamStatistics?
            if case .online = state.broadcast {
                liveStatistics = state.statistics
            } else {
                liveStatistics = nil
            }
            details.render(
                stateTitle: statusText(for: state.broadcast),
                reason: failureReason(for: state.broadcast),
                statistics: liveStatistics
            )
        }
    }

    private func microphoneTitle(for state: BroadcastScreenState) -> String {
        if viewModel.isMicrophoneSilencedByAccess {
            return "Silent"
        }
        return state.capture.isMicrophoneEnabled ? "Mic on" : "Muted"
    }

    private func statusText(for state: BroadcastState) -> String {
        switch state {
        case .offline:
            "Offline"
        case .connecting:
            "Connecting"
        case .online:
            "Online"
        case .reconnecting:
            "Reconnecting"
        case .failed:
            "Error"
        }
    }

    private func failureReason(for state: BroadcastState) -> String? {
        if case .failed(let error) = state { error.message } else { nil }
    }

    private func installBackControl() {
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Back",
            style: .plain,
            target: self,
            action: #selector(backTapped)
        )
    }

    private func configureViews() {
        previewContainer.translatesAutoresizingMaskIntoConstraints = false

        statusPanel.translatesAutoresizingMaskIntoConstraints = false
        statusPanel.addTarget(self, action: #selector(statusTapped), for: .touchUpInside)

        failureBanner.translatesAutoresizingMaskIntoConstraints = false
        failureBanner.isHidden = true
        failureBanner.onOpenSettings = { [weak self] in self?.openSystemSettings() }
        failureBanner.onRetry = { [weak self] in
            Task { await self?.viewModel.retryFailure() }
        }
        failureBanner.onDismiss = { [weak self] in self?.viewModel.dismissFailure() }

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Start"
        configuration.baseBackgroundColor = .systemRed
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        startStopButton.configuration = configuration
        startStopButton.translatesAutoresizingMaskIntoConstraints = false
        startStopButton.addTarget(self, action: #selector(startStopTapped), for: .touchUpInside)

        var cameraConfiguration = UIButton.Configuration.filled()
        cameraConfiguration.title = "Back camera"
        cameraConfiguration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        cameraConfiguration.baseForegroundColor = .white
        cameraConfiguration.cornerStyle = .capsule
        cameraButton.configuration = cameraConfiguration
        cameraButton.translatesAutoresizingMaskIntoConstraints = false
        cameraButton.addTarget(self, action: #selector(cameraTapped), for: .touchUpInside)

        var microphoneConfiguration = UIButton.Configuration.filled()
        microphoneConfiguration.title = "Mic on"
        microphoneConfiguration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        microphoneConfiguration.baseForegroundColor = .white
        microphoneConfiguration.cornerStyle = .capsule
        microphoneButton.configuration = microphoneConfiguration
        microphoneButton.translatesAutoresizingMaskIntoConstraints = false
        microphoneButton.addTarget(self, action: #selector(microphoneTapped), for: .touchUpInside)

        cameraUnavailableLabel.font = .preferredFont(forTextStyle: .caption1)
        cameraUnavailableLabel.textColor = .white
        cameraUnavailableLabel.textAlignment = .center
        cameraUnavailableLabel.numberOfLines = 0
        cameraUnavailableLabel.isHidden = true
        cameraUnavailableLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func layoutViews() {
        view.addSubview(previewContainer)
        view.addSubview(statusPanel)
        view.addSubview(failureBanner)
        view.addSubview(cameraUnavailableLabel)
        view.addSubview(cameraButton)
        view.addSubview(microphoneButton)
        view.addSubview(startStopButton)

        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: view.topAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            statusPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            statusPanel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusPanel.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            statusPanel.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),

            failureBanner.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            failureBanner.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            failureBanner.bottomAnchor.constraint(equalTo: cameraButton.topAnchor, constant: -16),

            startStopButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            startStopButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            startStopButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            startStopButton.heightAnchor.constraint(equalToConstant: 50),

            cameraButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            cameraButton.bottomAnchor.constraint(equalTo: startStopButton.topAnchor, constant: -16),
            cameraButton.heightAnchor.constraint(equalToConstant: 44),

            microphoneButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            microphoneButton.bottomAnchor.constraint(equalTo: startStopButton.topAnchor, constant: -16),
            microphoneButton.heightAnchor.constraint(equalToConstant: 44),

            cameraUnavailableLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            cameraUnavailableLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            cameraUnavailableLabel.bottomAnchor.constraint(equalTo: failureBanner.topAnchor, constant: -8),
        ])
    }

    private func observeLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @objc private func appDidEnterBackground() {
        Task { await viewModel.didLeaveForeground() }
    }

    @objc private func appDidBecomeActive() {
        Task { await viewModel.didBecomeActive() }
    }

    @objc private func startStopTapped() {
        Task {
            switch viewModel.state.broadcast {
            case .offline, .failed:
                await viewModel.start()
            case .connecting, .online, .reconnecting:
                await viewModel.stop()
            }
        }
    }

    @objc private func cameraTapped() {
        Task { await viewModel.switchCamera() }
    }

    @objc private func microphoneTapped() {
        Task { await viewModel.toggleMicrophone() }
    }

    @objc private func statusTapped() {
        guard viewModel.isStatusTappable, detailsController == nil else { return }
        presentDetails()
    }

    private func presentDetails() {
        let details = StreamDetailsViewController()
        details.render(
            stateTitle: statusText(for: viewModel.state.broadcast),
            reason: failureReason(for: viewModel.state.broadcast),
            statistics: viewModel.state.statistics
        )
        let navigation = UINavigationController(rootViewController: details)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        navigation.presentationController?.delegate = self
        detailsController = details
        present(navigation, animated: true)
    }

    @objc private func backTapped() {
        if viewModel.needsLeaveConfirmation {
            presentLeaveConfirmation()
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    private func presentLeaveConfirmation() {
        guard !isConfirmingLeave else { return }
        isConfirmingLeave = true
        let alert = UIAlertController(
            title: "Stop broadcasting?",
            message: "Leaving this screen will end the broadcast.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.isConfirmingLeave = false
        })
        alert.addAction(UIAlertAction(title: "Leave", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.isConfirmingLeave = false
            Task {
                await self.viewModel.confirmLeaving()
                self.navigationController?.popViewController(animated: true)
            }
        })
        present(alert, animated: true)
    }
}

private final class FailureBannerView: UIView {
    var onOpenSettings: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let messageLabel = UILabel()
    private let settingsButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)
    private let dismissButton = UIButton(type: .system)
    private let actionsStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.72)
        layer.cornerRadius = 12
        clipsToBounds = true

        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.textColor = .white
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        configureAction(settingsButton, title: "Open Settings", action: #selector(settingsTapped))
        configureAction(retryButton, title: "Retry", action: #selector(retryTapped))
        configureAction(dismissButton, title: "Dismiss", action: #selector(dismissTapped))

        actionsStack.axis = .horizontal
        actionsStack.spacing = 8
        actionsStack.distribution = .fillEqually
        actionsStack.addArrangedSubview(settingsButton)
        actionsStack.addArrangedSubview(retryButton)
        actionsStack.addArrangedSubview(dismissButton)

        let stack = UIStackView(arrangedSubviews: [messageLabel, actionsStack])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(error: BroadcastError) {
        messageLabel.text = error.message
        switch error.offeredAction {
        case .openSettings:
            settingsButton.isHidden = false
            retryButton.isHidden = false
            dismissButton.isHidden = true
        case .retry:
            settingsButton.isHidden = true
            retryButton.isHidden = false
            dismissButton.isHidden = true
        case .none:
            settingsButton.isHidden = true
            retryButton.isHidden = true
            dismissButton.isHidden = false
        }
    }

    func renderMicrophoneSilence(canOpenSettings: Bool) {
        messageLabel.text = BroadcastError.microphoneAccessDenied.message
        settingsButton.isHidden = !canOpenSettings
        retryButton.isHidden = true
        dismissButton.isHidden = true
    }

    private func configureAction(_ button: UIButton, title: String, action: Selector) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = .white
        configuration.baseForegroundColor = .black
        configuration.cornerStyle = .capsule
        button.configuration = configuration
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    @objc private func settingsTapped() { onOpenSettings?() }
    @objc private func retryTapped() { onRetry?() }
    @objc private func dismissTapped() { onDismiss?() }
}
