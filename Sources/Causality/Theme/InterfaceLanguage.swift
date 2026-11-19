import AppKit
import Foundation

enum InterfaceLanguage: String, CaseIterable {
    case system, simplified = "zh-Hans", english = "en", japanese = "ja", traditional = "zh-Hant"

    static let storageKey = "causal.interfaceLanguage"

    var identifier: String {
        if self != .system { return rawValue }
        return Bundle.main.preferredLocalizations.first ?? "zh-Hans"
    }

    var locale: Locale { Locale(identifier: identifier) }

    /// 英文界面用半角标点，中日文沿用全角。
    private var usesLatinPunctuation: Bool { identifier.hasPrefix("en") }

    var labelSeparator: String { usesLatinPunctuation ? ": " : "：" }
    var listSeparator: String { usesLatinPunctuation ? ", " : "、" }
    var columnSeparator: String { usesLatinPunctuation ? " " : "　" }

    static var labelSeparator: String { current.labelSeparator }
    static var listSeparator: String { current.listSeparator }
    static var columnSeparator: String { current.columnSeparator }

    var name: String {
        switch self {
        case .system: return label("跟随系统")
        case .simplified: return "简体中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .traditional: return "繁體中文"
        }
    }

    static var current: Self {
        let preference = UserDefaults.standard.string(forKey: storageKey) ?? "system"
        return Self(rawValue: preference) ?? .system
    }

    static func label(_ key: String) -> String {
        current.label(key)
    }

    /// 菜单栏、「关于」面板与窗口标题由 AppKit 按 bundle 的本地化解析，进程一启动就定了。
    /// 把当前选择写成进程自己的 `AppleLanguages`，下次启动整个 App（含 AppKit 文案）都按它解析。
    func applyBundleLanguage() {
        switch self {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        default:
            UserDefaults.standard.set([identifier], forKey: "AppleLanguages")
        }
    }

    /// 当前进程解析到的 bundle 语言，和选择的语言不一致时，菜单栏与「关于」还没换。
    static var bundleNeedsRestart: Bool {
        guard let resolved = Bundle.main.preferredLocalizations.first else { return false }
        return resolved != current.identifier
    }

    /// 换语言要重启才能让 AppKit 那几块跟上；开一个新实例，再关掉自己。
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func label(_ key: String) -> String {
        guard let url = Bundle.main.url(forResource: identifier, withExtension: "lproj"),
              let bundle = Bundle(url: url) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
