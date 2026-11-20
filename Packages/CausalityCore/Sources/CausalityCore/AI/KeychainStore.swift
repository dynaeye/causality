import Foundation
import Security

/// API key 只进钥匙串，项目文件与导出包都不带密钥。
public enum KeychainStore {
    private static let service = "tv.lzzy.causality.aikeys"
    public static func save(apiKey: String, for providerID: String) throws {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    public static func load(providerID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(providerID: String) {
        delete(service: service, providerID: providerID)
    }

    private static func delete(service: String, providerID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum KeychainError: Error, CustomStringConvertible {
    case unhandled(OSStatus)

    public var description: String {
        switch self {
        case let .unhandled(status): CoreText.format("钥匙串写入失败（OSStatus %lld）", Int(status))
        }
    }
}
