import Foundation
import CausalityCore

/// CLI 侧的语言开关：决定 Core 层的词条表，命令自身的提示跟着同一套词条走。
///
/// 优先级：显式 `--lang` > 故事板表头推断 > `LANG` > 简体中文。
enum CLILanguage {
    static func install(explicit: String?) {
        CoreText.install(language: normalized(explicit) ?? systemLanguage() ?? "zh-Hans")
    }

    static func install(explicit: String?, text: String) {
        let code = normalized(explicit)
            ?? detect(in: text)
            ?? systemLanguage()
            ?? "zh-Hans"
        CoreText.install(language: code)
    }

    /// 从故事板表头推断语言，作者不加 `--lang` 也能导入英文/日文表头。
    static func detect(in text: String) -> String? {
        let aliases = [
            ("Beat and Timing", "en"),
            ("ビートとタイミング", "ja"),
            ("節點與時機", "zh-Hant"),
        ]
        for (name, code) in aliases where text.contains(name) {
            return code
        }
        return nil
    }

    static func normalized(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return nil }
        if raw.hasPrefix("zh") {
            let traditional = raw.contains("hant") || raw.contains("tw") || raw.contains("hk") || raw.contains("mo")
            return traditional ? "zh-Hant" : "zh-Hans"
        }
        if raw.hasPrefix("ja") { return "ja" }
        if raw.hasPrefix("en") { return "en" }
        return nil
    }

    private static func systemLanguage() -> String? {
        normalized(ProcessInfo.processInfo.environment["LANG"])
    }
}
