import Foundation
import Security

public enum GroqKeychain {
    private static let service = "com.lumo.groq.apikey"
    private static let account = "LumoGroqAPIKey"
    
    public static func saveKey(_ key: String) {
        guard let data = key.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        // Delete any existing key
        SecItemDelete(query as CFDictionary)
        
        if !key.isEmpty {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            SecItemAdd(newQuery as CFDictionary, nil)
        }
    }
    
    public static func getKey() -> String? {
        // Fallback to env var for development
        if let envKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}
