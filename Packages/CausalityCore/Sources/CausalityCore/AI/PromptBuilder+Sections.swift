import Foundation

/// 把材料渲染成消息里的分节。
extension PromptBuilder {
    static func settingsSection(_ context: AIContext, localize: (String) -> String) -> [String] {
        guard !context.settings.isEmpty else { return [] }
        var lines = ["", localize("【已确定的事实设定】")]
        for setting in context.settings {
            let lock = setting.isLocked ? localize("（已锁定，不可改动）") : ""
            let body = setting.text.isEmpty ? "" : String(format: localize("：%@"), setting.text)
            lines.append("- \(setting.title)\(lock)\(body)")
        }
        return lines
    }

    static func nodesSection(_ context: AIContext, localize: (String) -> String) -> [String] {
        guard !context.nodes.isEmpty else { return [] }
        var lines = ["", localize("【场景】")]
        for node in context.nodes {
            lines.append(render(node: node, in: context, localize: localize))
        }
        return lines
    }

    static func edgesSection(_ context: AIContext, localize: (String) -> String) -> [String] {
        guard !context.edges.isEmpty else { return [] }
        var lines = ["", localize("【发展线】")]
        for edge in context.edges {
            lines.append(render(edge: edge, in: context, localize: localize))
        }
        return lines
    }

    static func castSection(_ context: AIContext, localize: (String) -> String) -> [String] {
        guard !context.characters.isEmpty || !context.places.isEmpty else { return [] }
        var lines = ["", localize("【人物与地点】")]
        if !context.characters.isEmpty {
            lines.append(
                String(
                    format: localize("- 人物：%@"),
                    context.characters.map(\.name).joined(separator: localize("、"))
                )
            )
        }
        if !context.places.isEmpty {
            lines.append(
                String(
                    format: localize("- 地点：%@"),
                    context.places.map(\.name).joined(separator: localize("、"))
                )
            )
        }
        return lines
    }

    static func captionsSection(_ context: AIContext, localize: (String) -> String) -> [String] {
        guard !context.assetCaptions.isEmpty else { return [] }
        var lines = ["", localize("【配图说明】")]
        for caption in context.assetCaptions {
            lines.append("- \(caption)")
        }
        return lines
    }

    static func render(edge: StoryEdge, in context: AIContext, localize: (String) -> String) -> String {
        let fromTitle = context.nodes.first { $0.id == edge.from }?.title
            ?? edge.from.rawValue.uuidString
        let toTitle = context.nodes.first { $0.id == edge.to }?.title
            ?? edge.to.rawValue.uuidString
        let condition = edge.condition.isEmpty
            ? ""
            : String(format: localize("（条件：%@）"), edge.condition)
        let head = String(
            format: localize("%@ → %@｜%@：%@"),
            fromTitle,
            toTitle,
            localize(edge.kind.displayName),
            edge.label
        )
        let id = String(format: localize("｜id=%@"), edge.id.rawValue.uuidString)
        return "- \(head)\(condition)\(id)"
    }

    static func render(node: StoryNode, in context: AIContext, localize: (String) -> String) -> String {
        var header = String(
            format: localize("- %@｜%@｜%@｜id=%@"),
            node.title,
            localize(node.kind.displayName),
            localize(node.status.displayName),
            node.id.rawValue.uuidString
        )
        if context.selection == node.id {
            header += localize("｜本轮选中")
        }
        var lines = [header]
        if !node.summary.isEmpty {
            lines.append(String(format: localize("摘要：%@"), node.summary))
        }
        if !node.body.isEmpty {
            lines.append(String(format: localize("正文：%@"), node.body.replacingOccurrences(of: "\n", with: " ")))
        }
        let names = context.characters.filter { node.characterIDs.contains($0.id) }.map(\.name)
        if !names.isEmpty {
            lines.append(String(format: localize("出场：%@"), names.joined(separator: localize("、"))))
        }
        let placeNames = context.places.filter { node.placeIDs.contains($0.id) }.map(\.name)
        if !placeNames.isEmpty {
            lines.append(String(format: localize("地点：%@"), placeNames.joined(separator: localize("、"))))
        }
        return lines.joined(separator: "\n")
    }
}
