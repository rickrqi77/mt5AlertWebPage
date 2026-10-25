import Foundation
import Security

enum KeychainStore {
    private static let service = "com.rickrqi77.goldalert"
    private static let tokenAccount = "api_token"
    private static let baseURLAccount = "api_base_url"

    static func saveToken(_ token: String) {
        save(account: tokenAccount, value: token)
    }

    static func readToken() -> String {
        read(account: tokenAccount) ?? ""
    }

    static func clearToken() {
        delete(account: tokenAccount)
    }

    static func saveBaseURL(_ url: String) {
        save(account: baseURLAccount, value: url)
    }

    static func readBaseURL() -> String {
        let saved = read(account: baseURLAccount)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if saved.isEmpty {
            return "https://alertdata.pages.dev"
        }
        return saved
    }

    private static func save(account: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
