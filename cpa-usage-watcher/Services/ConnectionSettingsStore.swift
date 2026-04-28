import Foundation
import Security

nonisolated protocol ManagementKeyStoring: Sendable {
    nonisolated func readManagementKey(service: String, account: String) throws -> String?
    nonisolated func saveManagementKey(_ managementKey: String, service: String, account: String) throws
    nonisolated func deleteManagementKey(service: String, account: String) throws
}

enum ConnectionSettingsStoreError: LocalizedError {
    case keychainReadFailed(OSStatus)
    case keychainSaveFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)
    case keychainInvalidData

    var errorDescription: String? {
        switch self {
        case let .keychainReadFailed(status):
            return "读取管理密钥失败：\(Self.message(for: status))"
        case let .keychainSaveFailed(status):
            return "保存管理密钥失败：\(Self.message(for: status))"
        case let .keychainDeleteFailed(status):
            return "删除管理密钥失败：\(Self.message(for: status))"
        case .keychainInvalidData:
            return "钥匙串中的管理密钥格式无效。"
        }
    }

    private static func message(for status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(message) (\(status))"
        }
        return "OSStatus \(status)"
    }
}

nonisolated final class ConnectionSettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let keychain: ManagementKeyStoring
    private let baseURLDefaultsKey: String
    private let keychainService: String
    private let keychainAccount: String

    init(
        defaults: UserDefaults = .standard,
        keychain: ManagementKeyStoring = SystemManagementKeyStore(),
        baseURLDefaultsKey: String = "usage.connection.baseURL",
        keychainService: String? = nil,
        keychainAccount: String = "management-key"
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.baseURLDefaultsKey = baseURLDefaultsKey
        self.keychainService = keychainService
            ?? Bundle.main.bundleIdentifier
            ?? "united-pooh.cpa-usage-watcher"
        self.keychainAccount = keychainAccount
    }

    nonisolated func load() throws -> ConnectionSettings {
        let baseURL = defaults.string(forKey: baseURLDefaultsKey) ?? ConnectionSettings.defaultBaseURL
        let managementKey = try keychain.readManagementKey(
            service: keychainService,
            account: keychainAccount
        ) ?? ""

        return ConnectionSettings(
            baseURL: sanitizedBaseURL(baseURL),
            managementKey: managementKey
        )
    }

    nonisolated func loadWithoutManagementKey() -> ConnectionSettings {
        let baseURL = defaults.string(forKey: baseURLDefaultsKey) ?? ConnectionSettings.defaultBaseURL
        return ConnectionSettings(baseURL: sanitizedBaseURL(baseURL), managementKey: "")
    }

    nonisolated func save(_ settings: ConnectionSettings) throws {
        defaults.set(sanitizedBaseURL(settings.baseURL), forKey: baseURLDefaultsKey)
        try saveManagementKey(settings.managementKey)
    }

    nonisolated func saveBaseURL(_ baseURL: String) {
        defaults.set(sanitizedBaseURL(baseURL), forKey: baseURLDefaultsKey)
    }

    nonisolated func saveManagementKey(_ managementKey: String) throws {
        try keychain.saveManagementKey(
            managementKey,
            service: keychainService,
            account: keychainAccount
        )
    }

    nonisolated func clearManagementKey() throws {
        try keychain.deleteManagementKey(
            service: keychainService,
            account: keychainAccount
        )
    }

    nonisolated func reset() throws {
        defaults.removeObject(forKey: baseURLDefaultsKey)
        try clearManagementKey()
    }

    nonisolated private func sanitizedBaseURL(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ConnectionSettings.defaultBaseURL
        }

        while trimmed.count > 1 && trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        return trimmed
    }
}

nonisolated struct SystemManagementKeyStore: ManagementKeyStoring {
    nonisolated func readManagementKey(service: String, account: String) throws -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw ConnectionSettingsStoreError.keychainReadFailed(status)
        }

        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw ConnectionSettingsStoreError.keychainInvalidData
        }

        return value
    }

    nonisolated func saveManagementKey(_ managementKey: String, service: String, account: String) throws {
        let trimmed = managementKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteManagementKey(service: service, account: account)
            return
        }

        let data = Data(trimmed.utf8)
        let query = baseQuery(service: service, account: account)
        let readStatus = SecItemCopyMatching(query as CFDictionary, nil)

        switch readStatus {
        case errSecSuccess:
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw ConnectionSettingsStoreError.keychainSaveFailed(updateStatus)
            }
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw ConnectionSettingsStoreError.keychainSaveFailed(addStatus)
            }
        default:
            throw ConnectionSettingsStoreError.keychainReadFailed(readStatus)
        }
    }

    nonisolated func deleteManagementKey(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ConnectionSettingsStoreError.keychainDeleteFailed(status)
        }
    }

    nonisolated private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
