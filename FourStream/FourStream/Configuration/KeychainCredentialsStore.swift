import Foundation
import Security

protocol CredentialsStoring: Sendable {
    func load() throws -> StreamCredentials?
    func save(_ credentials: StreamCredentials) throws
    func delete() throws
}

struct KeychainCredentialsStore: CredentialsStoring {
    private let service: String
    private let account: String

    init(
        service: String = "com.fourstream.credentials",
        account: String = "destination"
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> StreamCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unreadable
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let ingestURL = URL(string: payload.ingestURL) else {
            throw KeychainError.unreadable
        }
        return StreamCredentials(ingestURL: ingestURL, streamKey: payload.streamKey)
    }

    func save(_ credentials: StreamCredentials) throws {
        let data = try JSONEncoder().encode(
            Payload(
                ingestURL: credentials.ingestURL.absoluteString,
                streamKey: credentials.streamKey
            )
        )
        try delete()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unwritable
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unwritable
        }
    }
}

private struct Payload: Codable {
    var ingestURL: String
    var streamKey: String
}

private enum KeychainError: Error {
    case unreadable
    case unwritable
}
