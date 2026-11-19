import Foundation

/// Core 层文案的本地化入口。
///
/// 默认按 `zh-Hans` 从 `Bundle.module` 的词条表取，词条缺失时返回键本身；
/// 这与之前的恒等实现等价。App 启动时用 `InterfaceLanguage.label` 覆盖；
/// CLI 通过 `install(language:)` 切到 `--lang` 指定的词条表。
public enum CoreText {
    nonisolated(unsafe) public static var localize: @Sendable (String) -> String = localizer(for: "zh-Hans")

    public static func text(_ key: String) -> String {
        localize(key)
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localize(key), arguments: arguments)
    }

    /// 装某个语言的词条表。包内没有这个名字的 `.lproj` 时退回恒等。
    public static func install(language code: String) {
        localize = localizer(for: code)
    }

    /// 从 `Bundle.module` 取 `<code>.lproj`；取不到或词条缺失都回退到键本身。
    static func localizer(for code: String) -> @Sendable (String) -> String {
        guard let table = LocalizationTable(language: code) else { return { $0 } }
        return { table.text($0) }
    }

    /// `Bundle` 不是 `Sendable`；初始化后只读，跨线程查询是安全的。
    private final class LocalizationTable: @unchecked Sendable {
        private let bundle: Bundle

        init?(language code: String) {
            guard let url = Bundle.module.url(forResource: code, withExtension: "lproj"),
                  let bundle = Bundle(url: url) else { return nil }
            self.bundle = bundle
        }

        func text(_ key: String) -> String {
            bundle.localizedString(forKey: key, value: key, table: nil)
        }
    }
}
