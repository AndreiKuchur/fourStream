import UIKit

final class ConfigurationViewController: UIViewController {
    private let viewModel: ConfigurationViewModel
    private let makeBroadcastScreen: @MainActor (StreamCredentials) -> UIViewController

    private let addressField = UITextField()
    private let addressValidationLabel = UILabel()
    private let streamKeyField = UITextField()
    private let streamKeyValidationLabel = UILabel()
    private let generalValidationLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private var renderTask: Task<Void, Never>?

    /// The broadcasting screen is built by the composition root and handed over as a
    /// closure, so this screen never holds the streaming or permission boundaries.
    init(
        viewModel: ConfigurationViewModel,
        makeBroadcastScreen: @escaping @MainActor (StreamCredentials) -> UIViewController
    ) {
        self.viewModel = viewModel
        self.makeBroadcastScreen = makeBroadcastScreen
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stream Setup"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        configureViews()
        layoutViews()
        renderTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.viewModel.states {
                self.render(state)
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.prepareForEditing()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent {
            renderTask?.cancel()
        }
    }

    private func render(_ state: ConfigurationState) {
        switch state {
        case .form(let form):
            if addressField.text != form.ingestAddress {
                addressField.text = form.ingestAddress
            }
            if streamKeyField.text != form.streamKey {
                streamKeyField.text = form.streamKey
            }
            addressValidationLabel.text = form.addressValidationMessage
            addressValidationLabel.isHidden = form.addressValidationMessage == nil
            streamKeyValidationLabel.text = form.streamKeyValidationMessage
            streamKeyValidationLabel.isHidden = form.streamKeyValidationMessage == nil
            generalValidationLabel.text = form.generalValidationMessage
            generalValidationLabel.isHidden = form.generalValidationMessage == nil
            saveButton.isEnabled = form.isSaveEnabled
        case .readyToBroadcast(let credentials):
            showBroadcast(with: credentials)
            viewModel.prepareForEditing()
        }
    }

    private func showBroadcast(with credentials: StreamCredentials) {
        navigationController?.pushViewController(
            makeBroadcastScreen(credentials),
            animated: true
        )
    }

    private func configureViews() {
        addressField.placeholder = "Broadcast address"
        addressField.keyboardType = .URL
        addressField.autocapitalizationType = .none
        addressField.autocorrectionType = .no
        addressField.spellCheckingType = .no
        addressField.textContentType = .none
        addressField.borderStyle = .roundedRect
        addressField.accessibilityIdentifier = "ingestAddress"
        addressField.addTarget(self, action: #selector(addressChanged), for: .editingChanged)

        streamKeyField.placeholder = "Stream key"
        streamKeyField.isSecureTextEntry = true
        streamKeyField.autocapitalizationType = .none
        streamKeyField.autocorrectionType = .no
        streamKeyField.spellCheckingType = .no
        streamKeyField.textContentType = .oneTimeCode
        streamKeyField.borderStyle = .roundedRect
        streamKeyField.accessibilityIdentifier = "streamKey"
        streamKeyField.addTarget(self, action: #selector(streamKeyChanged), for: .editingChanged)

        configureValidationLabel(addressValidationLabel, identifier: "addressValidation")
        configureValidationLabel(streamKeyValidationLabel, identifier: "streamKeyValidation")
        configureValidationLabel(generalValidationLabel, identifier: "generalValidation")

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Save"
        saveButton.configuration = configuration
        saveButton.isEnabled = false
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        view.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        )
    }

    private func layoutViews() {
        let stack = UIStackView(arrangedSubviews: [
            addressField,
            addressValidationLabel,
            streamKeyField,
            streamKeyValidationLabel,
            generalValidationLabel,
            saveButton,
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            addressField.heightAnchor.constraint(equalToConstant: 44),
            streamKeyField.heightAnchor.constraint(equalToConstant: 44),
            saveButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    @objc private func addressChanged() {
        viewModel.updateAddress(addressField.text ?? "")
    }

    @objc private func streamKeyChanged() {
        viewModel.updateStreamKey(streamKeyField.text ?? "")
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        viewModel.save()
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private func configureValidationLabel(_ label: UILabel, identifier: String) {
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .systemRed
        label.numberOfLines = 0
        label.isHidden = true
        label.accessibilityIdentifier = identifier
    }
}
