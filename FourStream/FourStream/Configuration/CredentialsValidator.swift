import Foundation

enum CredentialsIssue: Equatable, Sendable {
    case missingAddress
    case missingKey
    case notABroadcastAddress

    var message: String {
        switch self {
        case .missingAddress:
            "The broadcast address is missing."
        case .missingKey:
            "The stream key is missing."
        case .notABroadcastAddress:
            "This is not a broadcast address."
        }
    }
}

enum CredentialsValidation: Equatable, Sendable {
    case valid(StreamCredentials)
    case invalid(CredentialsIssue)
}

enum CredentialsValidator {
    static func validate(address: String, streamKey: String) -> CredentialsValidation {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = streamKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedAddress.isEmpty {
            return .invalid(.missingAddress)
        }
        if trimmedKey.isEmpty {
            return .invalid(.missingKey)
        }

        guard let components = URLComponents(string: trimmedAddress),
              let scheme = components.scheme?.lowercased(),
              scheme == "rtmp" || scheme == "rtmps"
        else {
            return .invalid(.notABroadcastAddress)
        }

        guard let host = components.host, !host.isEmpty, let url = components.url else {
            return .invalid(.notABroadcastAddress)
        }

        return .valid(StreamCredentials(ingestURL: url, streamKey: trimmedKey))
    }
}
