import Foundation

struct ConfigurationForm: Equatable, Sendable {
    var ingestAddress: String
    var streamKey: String
    var addressValidationMessage: String?
    var streamKeyValidationMessage: String?
    var generalValidationMessage: String?
    var isSaveEnabled: Bool
}

enum ConfigurationState: Equatable, Sendable {
    case form(ConfigurationForm)
    case readyToBroadcast(StreamCredentials)
}

@MainActor
final class ConfigurationViewModel {
    private(set) var state: ConfigurationState
    let states: AsyncStream<ConfigurationState>

    private let store: any CredentialsStoring
    private let continuation: AsyncStream<ConfigurationState>.Continuation

    init(store: any CredentialsStoring) {
        self.store = store
        let (stream, continuation) = AsyncStream.makeStream(of: ConfigurationState.self)
        self.states = stream
        self.continuation = continuation

        do {
            if let saved = try store.load() {
                state = .form(Self.form(address: saved.ingestURL.absoluteString, streamKey: saved.streamKey))
            } else {
                state = .form(Self.form(address: "", streamKey: ""))
            }
        } catch {
            state = .form(
                ConfigurationForm(
                    ingestAddress: "",
                    streamKey: "",
                    addressValidationMessage: nil,
                    streamKeyValidationMessage: nil,
                    generalValidationMessage: "Saved credentials could not be loaded.",
                    isSaveEnabled: false
                )
            )
        }
        continuation.yield(state)
    }

    func updateAddress(_ address: String) {
        guard case .form(var form) = state else { return }
        form.ingestAddress = address
        form.addressValidationMessage = nil
        form.streamKeyValidationMessage = nil
        form.generalValidationMessage = nil
        form.isSaveEnabled = Self.canSave(address: form.ingestAddress, streamKey: form.streamKey)
        publish(.form(form))
    }

    func updateStreamKey(_ streamKey: String) {
        guard case .form(var form) = state else { return }
        form.streamKey = streamKey
        form.addressValidationMessage = nil
        form.streamKeyValidationMessage = nil
        form.generalValidationMessage = nil
        form.isSaveEnabled = Self.canSave(address: form.ingestAddress, streamKey: form.streamKey)
        publish(.form(form))
    }

    func save() {
        let form: ConfigurationForm
        switch state {
        case .form(let current):
            form = current
        case .readyToBroadcast(let credentials):
            form = Self.form(
                address: credentials.ingestURL.absoluteString,
                streamKey: credentials.streamKey
            )
        }

        switch CredentialsValidator.validate(address: form.ingestAddress, streamKey: form.streamKey) {
        case .valid(let credentials):
            do {
                try store.save(credentials)
                publish(.readyToBroadcast(credentials))
            } catch {
                var failed = form
                failed.addressValidationMessage = nil
                failed.streamKeyValidationMessage = nil
                failed.generalValidationMessage = "Credentials could not be saved."
                publish(.form(failed))
            }
        case .invalid(let issue):
            var invalid = form
            invalid.addressValidationMessage = nil
            invalid.streamKeyValidationMessage = nil
            invalid.generalValidationMessage = nil
            switch issue {
            case .missingAddress, .notABroadcastAddress:
                invalid.addressValidationMessage = issue.message
            case .missingKey:
                invalid.streamKeyValidationMessage = issue.message
            }
            invalid.isSaveEnabled = Self.canSave(address: form.ingestAddress, streamKey: form.streamKey)
            publish(.form(invalid))
        }
    }

    func prepareForEditing() {
        guard case .readyToBroadcast(let credentials) = state else { return }
        publish(
            .form(
                Self.form(
                    address: credentials.ingestURL.absoluteString,
                    streamKey: credentials.streamKey
                )
            )
        )
    }

    private func publish(_ state: ConfigurationState) {
        self.state = state
        continuation.yield(state)
    }

    private static func form(address: String, streamKey: String) -> ConfigurationForm {
        ConfigurationForm(
            ingestAddress: address,
            streamKey: streamKey,
            addressValidationMessage: nil,
            streamKeyValidationMessage: nil,
            generalValidationMessage: nil,
            isSaveEnabled: canSave(address: address, streamKey: streamKey)
        )
    }

    private static func canSave(address: String, streamKey: String) -> Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !streamKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
