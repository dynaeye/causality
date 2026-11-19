import Foundation
import Testing
@testable import CausalityCore

/// 英文复数：128 个计数词条里有 44 个走 `.stringsdict`，`1 card` 不该写成 `1 cards`。
@Suite("词条的复数规则")
struct PluralLocalizationTests {
    private let english = CoreText.localizer(for: "en")

    private func text(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: english(key), arguments: arguments)
    }

    @Test("英文的计数名词按单复数分开")
    func englishPlurals() {
        #expect(text("%lld 张卡", 1) == "1 card")
        #expect(text("%lld 张卡", 3) == "3 cards")
        #expect(text("%lld 场", 1) == "1 scene")
        #expect(text("%lld 个结局", 2) == "2 endings")
        #expect(text("%lld 步", 1) == "1 step")
        #expect(text("%lld 项建议", 1) == "1 suggestion")
        #expect(text("%lld 人 × %lld 章", 1, 1) == "1 character × 1 chapter")
        #expect(text("%lld 人 × %lld 章", 2, 3) == "2 characters × 3 chapters")
        #expect(text("%lld 张 · %lld 字", 1, 1) == "1 card · 1 word")
        #expect(text("【%@】 %lld 张", "第一幕", 1) == "[第一幕] 1 card")
        #expect(text("%lld 张 与 %lld 张", 0, 0) == "0 张 与 0 张", "未登记的键原样返回")
    }

    @Test("零与多数走 other")
    func zeroAndMany() {
        #expect(text("%lld 张卡", 0) == "0 cards")
        #expect(text("%lld 张卡", 11) == "11 cards")
    }

    @Test("中文与日文没有复数变化")
    func chineseStaysFlat() {
        let simplified = CoreText.localizer(for: "zh-Hans")
        #expect(String(format: simplified("%lld 张卡"), 1) == "1 张卡")
        let japanese = CoreText.localizer(for: "ja")
        #expect(String(format: japanese("%lld 张卡"), 1) == "1 枚のカード")
    }
}
