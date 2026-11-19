import Foundation

/// 试读稿：给编剧通读用的逐场正文，带选项记录与累计字数。
public enum PlaythroughMarkdown {
    public static func render(
        _ playthrough: Playthrough,
        project: StoryProject,
        localize: (String) -> String = { $0 }
    ) -> String {
        var lines = [String(format: localize("# 《%@》试读稿"), project.title), ""]
        for step in playthrough.steps {
            let chapter = step.node.chapterID.flatMap { project.chapter($0)?.title } ?? localize("未分章")
            lines.append("## \(step.stepNumber). \(chapter) · \(step.node.title)")
            if let choice = step.incomingLabel, !choice.isEmpty {
                lines.append(String(format: localize("> 选项：%@"), choice))
                lines.append("")
            }
            lines.append(step.node.body.isEmpty ? localize("（空场）") : step.node.body)
            lines.append("")
        }
        lines.append("---")
        lines.append(
            String(
                format: localize("共 %lld 步，累计 %lld 字。"),
                playthrough.stepCount,
                playthrough.cumulativeWords
            )
        )
        return lines.joined(separator: "\n")
    }
}
