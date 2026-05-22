import Foundation
import Security

enum KeychainStore {
    struct ClaudeCredentials: Codable {
        var sessionKey: String
        var cfClearance: String
    }

    private static let service = "com.local.ModelMeter"
    private static let legacyService = "com.local.LLMUsageTracker"
    private static let claudeCredentialsAccount = "claudeCredentials"
    private static let legacySessionKeyAccount = "claudeSessionKey"
    private static let legacyClearanceAccount = "claudeCfClearance"
    static func readClaudeCredentials(allowPrompt: Bool = false) -> ClaudeCredentials {
        if let value = read(account: claudeCredentialsAccount, service: service, allowPrompt: allowPrompt),
           let data = value.data(using: .utf8),
           let credentials = try? JSONDecoder().decode(ClaudeCredentials.self, from: data) {
            return credentials
        }

        let sessionKey = read(account: legacySessionKeyAccount, service: service, allowPrompt: allowPrompt)
            ?? read(account: legacySessionKeyAccount, service: legacyService, allowPrompt: allowPrompt)
            ?? ""
        let cfClearance = read(account: legacyClearanceAccount, service: service, allowPrompt: allowPrompt)
            ?? read(account: legacyClearanceAccount, service: legacyService, allowPrompt: allowPrompt)
            ?? ""
        return ClaudeCredentials(sessionKey: sessionKey, cfClearance: cfClearance)
    }

    @discardableResult
    static func clearClaudeCredentials() -> OSStatus {
        let statuses = [
            delete(account: claudeCredentialsAccount, service: service),
            delete(account: legacySessionKeyAccount, service: service),
            delete(account: legacyClearanceAccount, service: service),
            delete(account: legacySessionKeyAccount, service: legacyService),
            delete(account: legacyClearanceAccount, service: legacyService)
        ]
        return statuses.first { $0 != errSecSuccess && $0 != errSecItemNotFound } ?? errSecSuccess
    }

    @discardableResult
    static func writeClaudeCredentials(_ credentials: ClaudeCredentials) -> OSStatus {
        if credentials.sessionKey.isEmpty && credentials.cfClearance.isEmpty {
            return clearClaudeCredentials()
        }

        let data: Data
        do {
            data = try JSONEncoder().encode(credentials)
        } catch {
            return errSecParam
        }
        guard let value = String(data: data, encoding: .utf8) else { return errSecParam }
        let status = write(value, account: claudeCredentialsAccount)
        if status == errSecSuccess {
            _ = delete(account: legacySessionKeyAccount, service: service)
            _ = delete(account: legacyClearanceAccount, service: service)
            _ = delete(account: legacySessionKeyAccount, service: legacyService)
            _ = delete(account: legacyClearanceAccount, service: legacyService)
        }
        return status
    }

    static func read(account: String, allowPrompt: Bool = false) -> String {
        if let value = read(account: account, service: service, allowPrompt: allowPrompt) {
            return value
        }
        guard let legacyValue = read(account: account, service: legacyService, allowPrompt: allowPrompt) else {
            return ""
        }
        _ = write(legacyValue, account: account)
        return legacyValue
    }

    private static func read(account: String, service: String, allowPrompt: Bool) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if !allowPrompt {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return value
    }

    @discardableResult
    static func write(_ value: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if value.isEmpty {
            return SecItemDelete(query as CFDictionary)
        }

        let data = Data(value.utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            return status
        }
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(add as CFDictionary, nil)
        }
        return status
    }

    @discardableResult
    private static func delete(account: String, service: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(query as CFDictionary)
    }

    static func statusDescription(_ status: OSStatus) -> String {
        if status == errSecSuccess { return "success" }
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(message) (OSStatus \(status))"
        }
        return "OSStatus \(status)"
    }
}
