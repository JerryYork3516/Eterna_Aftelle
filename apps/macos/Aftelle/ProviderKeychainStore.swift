import Foundation
import Security

nonisolated final class ProviderKeychainStore: ProviderCredentialReading, @unchecked Sendable {
    static let service = "com.eterna.aftelle.provider.deepseek"
    static let account = "primary-text-llm"
    static let keyRef = "keychain://com.eterna.aftelle.provider.deepseek/primary-text-llm"

    func save(_ credential: String, for keyRef: String) throws {
        guard keyRef == Self.keyRef else {
            throw ProviderKeychainError.unsupportedReference
        }
        let value = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let data = value.data(using: .utf8) else {
            throw ProviderKeychainError.invalidCredential
        }

        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw ProviderKeychainError.operationFailed
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw ProviderKeychainError.operationFailed
        }
    }

    func readCredential(for keyRef: String) throws -> String? {
        guard keyRef == Self.keyRef else {
            throw ProviderKeychainError.unsupportedReference
        }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let credential = String(data: data, encoding: .utf8) else {
            throw ProviderKeychainError.operationFailed
        }
        return credential
    }

    func exists(for keyRef: String) -> Bool {
        guard keyRef == Self.keyRef else { return false }
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func delete(for keyRef: String) throws {
        guard keyRef == Self.keyRef else {
            throw ProviderKeychainError.unsupportedReference
        }
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProviderKeychainError.operationFailed
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}

private enum ProviderKeychainError: Error {
    case invalidCredential
    case unsupportedReference
    case operationFailed
}
