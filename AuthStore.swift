import Foundation
import Security

class AuthStore {
    static let shared = AuthStore()
    private let tokenKey = "cosmic_auth_token"
    private let usernameKey = "cosmic_auth_username"

    var token: String? {
        get { readKeychain(tokenKey) }
        set { if let v = newValue { writeKeychain(tokenKey, v) } else { deleteKeychain(tokenKey) } }
    }
    var username: String? {
        get { readKeychain(usernameKey) }
        set { if let v = newValue { writeKeychain(usernameKey, v) } else { deleteKeychain(usernameKey) } }
    }
    func clear() { deleteKeychain(tokenKey); deleteKeychain(usernameKey) }

    private func writeKeychain(_ key: String, _ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    private func readKeychain(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private func deleteKeychain(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
