import Foundation
import Security

nonisolated final class ProviderKeychainStore: ProviderCredentialReading, @unchecked Sendable {
    static let service = "com.eterna.aftelle.provider.deepseek"
    static let account = "primary-text-llm"
    static let keyRef = "keychain://com.eterna.aftelle.provider.deepseek/primary-text-llm"
    static let stepFunService = "com.eterna.aftelle.provider.stepfun"
    static let stepFunAccount = "stepfun_realtime_api_key"
    static let stepFunKeyRef =
        "keychain://com.eterna.aftelle.provider.stepfun/stepfun_realtime_api_key"
    static let qwenService = "com.eterna.aftelle.provider.qwen"
    static let qwenAccount = "qwen_realtime_credential"
    static let qwenKeyRef =
        "keychain://com.eterna.aftelle.provider.qwen/qwen_realtime_credential"

    func save(_ credential: String, for keyRef: String) throws {
        let query = try baseQuery(for: keyRef)
        let value = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let data = value.data(using: .utf8) else {
            throw ProviderKeychainError.invalidCredential
        }

        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw ProviderKeychainError.operationFailed
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw ProviderKeychainError.operationFailed
        }
    }

    func readCredential(for keyRef: String) throws -> String? {
        var query = try baseQuery(for: keyRef)
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
        guard var query = try? baseQuery(for: keyRef) else { return false }
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func delete(for keyRef: String) throws {
        let query = try baseQuery(for: keyRef)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProviderKeychainError.operationFailed
        }
    }

    static func location(for keyRef: String) -> (service: String, account: String)? {
        switch keyRef {
        case Self.keyRef:
            return (Self.service, Self.account)
        case Self.stepFunKeyRef:
            return (Self.stepFunService, Self.stepFunAccount)
        case Self.qwenKeyRef:
            return (Self.qwenService, Self.qwenAccount)
        default:
            return nil
        }
    }

    private func baseQuery(for keyRef: String) throws -> [String: Any] {
        guard let location = Self.location(for: keyRef) else {
            throw ProviderKeychainError.unsupportedReference
        }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: location.service,
            kSecAttrAccount as String: location.account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}

private enum ProviderKeychainError: Error {
    case invalidCredential
    case unsupportedReference
    case operationFailed
}
