import Foundation

/// Markdown 导入的统一入口：有故事板表走表格导入，普通标题/段落走散文导入。
public enum MarkdownImport {
    public enum Mode: String, Sendable {
        case storyboard
        case prose
    }

    public struct Result: Sendable {
        public var project: StoryProject
        public var mode: Mode
        public var notes: [String]
    }

    /// 一行以 `|` 开头且首格是「节点与时机」（或当前语言的对应表头）才算故事板表；
    /// 正文里提到这几个字不会误判。
    public static func detectMode(
        _ text: String,
        localize: (String) -> String = { CoreText.localize($0) }
    ) -> Mode {
        let hasBoard = text.components(separatedBy: .newlines).contains { line in
            StoryboardMarkdown.isBoardHeader(line: line, localize: localize)
        }
        return hasBoard ? .storyboard : .prose
    }

    public static func makeProject(
        fromMarkdown text: String,
        title: String = "",
        forcedMode: Mode? = nil,
        localize: (String) -> String = { CoreText.localize($0) }
    ) throws -> Result {
        let mode = forcedMode ?? detectMode(text, localize: localize)
        switch mode {
        case .storyboard:
            let project = try StoryboardMarkdown.makeProject(
                fromMarkdown: text,
                title: title,
                localize: localize
            )
            return Result(project: project, mode: .storyboard, notes: [])
        case .prose:
            let project = try ProseMarkdown.makeProject(fromMarkdown: text, title: title)
            let scenes = project.nodes.count { $0.status == .draft }
            return Result(
                project: project,
                mode: .prose,
                notes: ["按普通 Markdown 导入：\(project.chapters.count) 章 \(scenes) 场。"]
            )
        }
    }
}
