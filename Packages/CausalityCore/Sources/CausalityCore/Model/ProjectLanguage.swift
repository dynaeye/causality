import Foundation
import NaturalLanguage

/// 作品内容语言。导出与 AI 提示词跟着它走，不跟界面语言走。
public enum ProjectLanguage: String, Sendable, CaseIterable {
    case english = "en"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    public var localeIdentifier: String { rawValue }

    /// 从作品正文判断语言。材料太少或判断不出时返回 nil，由调用方回落到界面语言。
    public static func detect(in project: StoryProject) -> ProjectLanguage? {
        var parts: [String] = [project.title]
        if !project.logline.isEmpty { parts.append(project.logline) }
        parts.append(contentsOf: project.chapters.map(\.title))
        for node in project.nodes.prefix(40) {
            parts.append(node.title)
            if !node.summary.isEmpty { parts.append(node.summary) }
            if !node.body.isEmpty { parts.append(String(node.body.prefix(240))) }
        }
        let sample = parts
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(sample.prefix(4000)))
        switch recognizer.dominantLanguage {
        case .english: return .english
        case .japanese: return .japanese
        case .simplifiedChinese: return .simplifiedChinese
        case .traditionalChinese: return .traditionalChinese
        default: return nil
        }
    }
}
