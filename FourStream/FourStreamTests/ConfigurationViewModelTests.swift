import Foundation
import Testing
@testable import FourStream

@MainActor
struct ConfigurationViewModelTests {

    // MARK: - Saved credentials

    @Test
    func firstLaunchOffersAnEmptyFormThatCannotBeSaved() {
        let viewModel = ConfigurationViewModel(store: CredentialsStoreDouble())

        let form = Self.form(of: viewModel)
        #expect(form?.ingestAddress == "")
        #expect(form?.streamKey == "")
        #expect(form?.isSaveEnabled == false)
        #expect(form?.generalValidationMessage == nil)
    }

    @Test
    func savedCredentialsArePreFilled() {
        let store = CredentialsStoreDouble(stored: .stub())
        let viewModel = ConfigurationViewModel(store: store)

        let form = Self.form(of: viewModel)
        #expect(form?.ingestAddress == "rtmp://live.example.com/app")
        #expect(form?.streamKey == "live_secret_key_value")
        #expect(form?.isSaveEnabled == true)
    }

    @Test
    func credentialsThatCannotBeReadAreReportedRatherThanSilentlyLost() {
        let store = CredentialsStoreDouble()
        store.loadError = .unavailable
        let viewModel = ConfigurationViewModel(store: store)

        let form = Self.form(of: viewModel)
        #expect(form?.generalValidationMessage == "Saved credentials could not be loaded.")
        #expect(form?.isSaveEnabled == false)
    }

    @Test
    func aFailedSaveKeepsTheUserOnTheFormWithAnExplanation() {
        let store = CredentialsStoreDouble()
        store.saveError = .unavailable
        let viewModel = ConfigurationViewModel(store: store)
        viewModel.updateAddress("rtmp://live.example.com/app")
        viewModel.updateStreamKey("key")

        viewModel.save()

        #expect(Self.form(of: viewModel)?.generalValidationMessage == "Credentials could not be saved.")
        #expect(store.stored == nil)
    }

    @Test
    func changedCredentialsReplaceTheStoredOnes() {
        let store = CredentialsStoreDouble(stored: .stub())
        let viewModel = ConfigurationViewModel(store: store)

        viewModel.updateAddress("rtmps://other.example.com/live")
        viewModel.updateStreamKey("second_key")
        viewModel.save()

        #expect(store.stored?.ingestURL.absoluteString == "rtmps://other.example.com/live")
        #expect(store.stored?.streamKey == "second_key")
        #expect(store.saveCount == 1)
    }

    // MARK: - Validation before any connection

    @Test
    func anAddressThatIsNotABroadcastAddressIsRejectedWithoutSaving() {
        let store = CredentialsStoreDouble()
        let viewModel = ConfigurationViewModel(store: store)
        viewModel.updateAddress("https://example.com/live")
        viewModel.updateStreamKey("key")

        viewModel.save()

        let form = Self.form(of: viewModel)
        #expect(form?.addressValidationMessage == "This is not a broadcast address.")
        #expect(form?.streamKeyValidationMessage == nil)
        #expect(store.saveCount == 0)
    }

    @Test
    func aWhitespaceOnlyKeyIsNamedAsTheMissingField() {
        let store = CredentialsStoreDouble()
        let viewModel = ConfigurationViewModel(store: store)
        viewModel.updateAddress("rtmp://live.example.com/app")
        viewModel.updateStreamKey("   ")

        viewModel.save()

        let form = Self.form(of: viewModel)
        #expect(form?.streamKeyValidationMessage == "The stream key is missing.")
        #expect(form?.addressValidationMessage == nil)
        #expect(store.saveCount == 0)
    }

    @Test
    func savingIsDisabledUntilBothFieldsCarrySomething() {
        let viewModel = ConfigurationViewModel(store: CredentialsStoreDouble())

        viewModel.updateAddress("rtmp://live.example.com/app")
        #expect(Self.form(of: viewModel)?.isSaveEnabled == false)

        viewModel.updateStreamKey("  ")
        #expect(Self.form(of: viewModel)?.isSaveEnabled == false)

        viewModel.updateStreamKey("key")
        #expect(Self.form(of: viewModel)?.isSaveEnabled == true)
    }

    @Test
    func editingClearsTheMessageFromThePreviousAttempt() {
        let viewModel = ConfigurationViewModel(store: CredentialsStoreDouble())
        viewModel.updateAddress("https://example.com/live")
        viewModel.updateStreamKey("key")
        viewModel.save()
        #expect(Self.form(of: viewModel)?.addressValidationMessage != nil)

        viewModel.updateAddress("rtmp://live.example.com/app")

        #expect(Self.form(of: viewModel)?.addressValidationMessage == nil)
    }

    // MARK: - Proceeding to the broadcast

    @Test
    func validCredentialsAreStoredTrimmedAndOpenTheBroadcast() {
        let store = CredentialsStoreDouble()
        let viewModel = ConfigurationViewModel(store: store)
        viewModel.updateAddress("  rtmp://live.example.com/app\n")
        viewModel.updateStreamKey(" live_key \n")

        viewModel.save()

        guard case .readyToBroadcast(let credentials) = viewModel.state else {
            Issue.record("expected readyToBroadcast, got \(viewModel.state)")
            return
        }
        #expect(credentials.ingestURL.absoluteString == "rtmp://live.example.com/app")
        #expect(credentials.streamKey == "live_key")
        #expect(store.stored == credentials)
    }

    @Test
    func returningToTheFormKeepsTheSavedValuesEditable() {
        let viewModel = ConfigurationViewModel(store: CredentialsStoreDouble())
        viewModel.updateAddress("rtmp://live.example.com/app")
        viewModel.updateStreamKey("live_key")
        viewModel.save()

        viewModel.prepareForEditing()

        let form = Self.form(of: viewModel)
        #expect(form?.ingestAddress == "rtmp://live.example.com/app")
        #expect(form?.streamKey == "live_key")
        #expect(form?.isSaveEnabled == true)
    }

    // MARK: - Helpers

    private static func form(of viewModel: ConfigurationViewModel) -> ConfigurationForm? {
        if case .form(let form) = viewModel.state { form } else { nil }
    }
}
