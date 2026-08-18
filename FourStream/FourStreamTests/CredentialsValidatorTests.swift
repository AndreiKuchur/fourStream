import Foundation
import Testing
@testable import FourStream

struct CredentialsValidatorTests {
    @Test
    func validRTMPAddressIsAccepted() {
        let result = CredentialsValidator.validate(
            address: "rtmp://live.example.com/app",
            streamKey: "live_key"
        )

        guard case .valid(let credentials) = result else {
            Issue.record("expected valid, got \(result)")
            return
        }
        #expect(credentials.ingestURL.absoluteString == "rtmp://live.example.com/app")
        #expect(credentials.streamKey == "live_key")
    }

    @Test
    func validRTMPSAddressIsAccepted() {
        let result = CredentialsValidator.validate(
            address: "rtmps://live.example.com/app",
            streamKey: "live_key"
        )

        guard case .valid(let credentials) = result else {
            Issue.record("expected valid, got \(result)")
            return
        }
        #expect(credentials.ingestURL.scheme == "rtmps")
        #expect(credentials.ingestURL.host == "live.example.com")
    }

    @Test
    func schemeIsMatchedCaseInsensitively() {
        let result = CredentialsValidator.validate(
            address: "RTMPS://live.example.com/app",
            streamKey: "live_key"
        )

        guard case .valid = result else {
            Issue.record("expected valid, got \(result)")
            return
        }
    }

    @Test
    func pastedTrailingNewlineIsTrimmed() {
        let result = CredentialsValidator.validate(
            address: "rtmp://live.example.com/app\n",
            streamKey: "live_key\n"
        )

        guard case .valid(let credentials) = result else {
            Issue.record("expected valid, got \(result)")
            return
        }
        #expect(credentials.ingestURL.absoluteString == "rtmp://live.example.com/app")
        #expect(credentials.streamKey == "live_key")
    }

    @Test
    func surroundingSpacesOnTheKeyAreTrimmed() {
        let result = CredentialsValidator.validate(
            address: "rtmp://live.example.com/app",
            streamKey: "  live_key  "
        )

        guard case .valid(let credentials) = result else {
            Issue.record("expected valid, got \(result)")
            return
        }
        #expect(credentials.streamKey == "live_key")
    }

    @Test
    func httpsSchemeIsRejectedAsNotABroadcastAddress() {
        let result = CredentialsValidator.validate(
            address: "https://live.example.com/app",
            streamKey: "live_key"
        )

        guard case .invalid(let issue) = result else {
            Issue.record("expected invalid, got \(result)")
            return
        }
        #expect(issue == .notABroadcastAddress)
        #expect(issue.message.lowercased().contains("broadcast address"))
    }

    @Test
    func bareHostWithNoSchemeIsRejected() {
        let result = CredentialsValidator.validate(
            address: "live.example.com/app",
            streamKey: "live_key"
        )

        guard case .invalid(let issue) = result else {
            Issue.record("expected invalid, got \(result)")
            return
        }
        #expect(issue == .notABroadcastAddress)
    }

    @Test
    func emptyAddressNamesTheMissingField() {
        let result = CredentialsValidator.validate(address: "", streamKey: "live_key")

        guard case .invalid(let issue) = result else {
            Issue.record("expected invalid, got \(result)")
            return
        }
        #expect(issue == .missingAddress)
        #expect(issue.message.lowercased().contains("address"))
    }

    @Test
    func emptyKeyNamesTheMissingField() {
        let result = CredentialsValidator.validate(
            address: "rtmp://live.example.com/app",
            streamKey: ""
        )

        guard case .invalid(let issue) = result else {
            Issue.record("expected invalid, got \(result)")
            return
        }
        #expect(issue == .missingKey)
        #expect(issue.message.lowercased().contains("key"))
    }

    @Test
    func whitespaceOnlyAddressIsTreatedAsMissing() {
        let result = CredentialsValidator.validate(
            address: " \n\t ",
            streamKey: "live_key"
        )

        guard case .invalid(let issue) = result else {
            Issue.record("expected invalid, got \(result)")
            return
        }
        #expect(issue == .missingAddress)
    }

    @Test
    func whitespaceOnlyKeyIsTreatedAsMissing() {
        let result = CredentialsValidator.validate(
            address: "rtmp://live.example.com/app",
            streamKey: " \n "
        )

        guard case .invalid(let issue) = result else {
            Issue.record("expected invalid, got \(result)")
            return
        }
        #expect(issue == .missingKey)
    }

    @Test
    func addressWithoutHostIsRejected() {
        let result = CredentialsValidator.validate(
            address: "rtmp://",
            streamKey: "live_key"
        )

        guard case .invalid(let issue) = result else {
            Issue.record("expected invalid, got \(result)")
            return
        }
        #expect(issue == .notABroadcastAddress)
    }
}
