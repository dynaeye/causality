import Foundation

/// 密钥的三层来源：环境变量 → Release 钥匙串 → Debug 的 0600 文件。
///
/// 调试构建每次重签都会被钥匙串当成新 App，反复弹授权，所以 Debug 用 Application Support
/// 里的一个 0600 plist；Release 走钥匙串。环境变量优先级最高，方便 CLI 与临时联调。
public enum AICredentialStore {
    private static let directoryName = "Causality"

    private static var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    public static var directory: URL {
        base.appendingPathComponent(directoryName, isDirectory: true)
    }

    public static var fileURL: URL {
        directory.appendingPathComponent("credentials.plist")
    }

    public static func load(providerID: String) -> String? {
        if let value = environmentValue(for: providerID), !value.isEmpty {
            return value
        }
        #if !DEBUG
        if let value = KeychainStore.load(providerID: providerID), !value.isEmpty {
            return value
        }
        #endif
        let value = all()[providerID]
        return (value?.isEmpty ?? true) ? nil : value
    }

    public static func save(_ key: String, for providerID: String) throws {
        #if DEBUG
        var values = all()
        values[providerID] = key
        try write(values)
        #else
        do {
            try KeychainStore.save(apiKey: key, for: providerID)
        } catch {
            // 钥匙串被锁或沙箱拒绝时，退到 0600 文件，至少不丢这次输入。
            var values = all()
            values[providerID] = key
            try write(values)
        }
        #endif
    }

    public static func delete(providerID: String) {
        KeychainStore.delete(providerID: providerID)
        var values = all()
        values.removeValue(forKey: providerID)
        try? write(values)
    }

    /// 与 CLI 的 `credential(for:)` 用同一组环境变量名。
    private static func environmentValue(for providerID: String) -> String? {
        let names: [String]
        switch providerID {
        case "openai":
            names = ["CAUSAL_OPENAI_KEY", "OPENAI_API_KEY"]
        case "opencode-go":
            names = ["CAUSAL_OPENCODE_KEY", "OPENCODE_API_KEY"]
        case "deepseek":
            names = ["CAUSAL_DEEPSEEK_KEY", "DEEPSEEK_API_KEY"]
        case "minimax-cn":
            names = ["CAUSAL_MINIMAX_KEY", "MINIMAX_API_KEY"]
        default:
            names = []
        }
        for name in names {
            if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    public static func all() -> [String: String] {
        read(fileURL) ?? [:]
    }

    private static func read(_ url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = plist as? [String: String] else {
            return nil
        }
        return values
    }

    private static func write(_ values: [String: String]) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
