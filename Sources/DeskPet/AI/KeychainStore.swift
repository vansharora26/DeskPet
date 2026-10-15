import Foundation
import Security

/// Stores the API key in the user's login Keychain — never in source code,
/// UserDefaults, plain files, logs, or the app binary.
enum KeychainStore {
    private static let service = "app.deskpet.DeskPet.anthropic"
    private static let account = "api-key"

    enum KeychainError: Error, LocalizedError {
        case status(OSStatus)
        var errorDescription: String? {
            if case .status(let s) = self {
                return (SecCopyErrorMessageString(s, nil) as String?) ?? "Keychain error \(s)"
            }
            return nil
        }
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func saveAPIKey(_ key: String) throws {
        let data = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func loadAPIKey() -> String? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        let key = String(data: data, encoding: .utf8)
        return (key?.isEmpty ?? true) ? nil : key
    }

    static func deleteAPIKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    static var hasAPIKey: Bool { loadAPIKey() != nil }
}
