import Foundation

/// 一份 Markdown 导出稿，以及正文里引到的配图。
public struct OutlineMarkdownDocument: Sendable, Equatable {
    public var markdown: String
    /// 正文以 `assets/<文件名>` 引用的图片，导出时一起复制。
    public var assetFileNames: [String]
}

/// 从同一份大纲快照生成 Markdown。与界面共用 `OutlineBuilder`，不另写一套推导。
public enum OutlineMarkdown {
    public static func render(project: StoryProject) -> String {
        document(project: project).markdown
    }

    /// 只导出通往某个结局的路径。
    public static func render(project: StoryProject, route: StoryRoute) -> String {
        document(project: project, route: route).markdown
    }

    public static func render(project: StoryProject, outlines: [ChapterOutline], routeTitle: String? = nil) -> String {
        document(project: project, outlines: outlines, routeTitle: routeTitle).markdown
    }

    public static func document(project: StoryProject, label: (String) -> String = { $0 }) -> OutlineMarkdownDocument {
        document(project: project, outlines: OutlineBuilder.build(project: project), label: label)
    }

    /// 只导出通往某个结局的路径。
    public static func document(project: StoryProject, route: StoryRoute, label: (String) -> String = { $0 }) -> OutlineMarkdownDocument {
        let index = project.makeIndex()
        let outlines = OutlineBuilder.build(project: project, index: index, nodes: route.nodeIDs)
            .filter { !$0.rows.isEmpty }
        let endingTitle = index.nodeByID[route.endingID]?.title ?? label("结局")
        return document(project: project, outlines: outlines, routeTitle: endingTitle, label: label)
    }

    public static func document(
        project: StoryProject,
        outlines: [ChapterOutline],
        routeTitle: String? = nil,
        label: (String) -> String = { $0 }
    ) -> OutlineMarkdownDocument {
        let index = project.makeIndex()
        var assets: Set<String> = []
        var lines: [String] = []
        lines.append("# \(project.title)")
        if let routeTitle {
            lines.append("")
            lines.append("> " + String(format: label("只含通往「%@」的路径。"), routeTitle))
        }
        if !project.logline.isEmpty {
            lines.append("")
            lines.append(project.logline)
        }

        for outline in outlines {
            lines.append("")
            lines.append("## \(outline.chapterTitle)")
            if !outline.chapterSummary.isEmpty {
                lines.append("")
                lines.append(outline.chapterSummary)
            }
            for row in outline.rows {
                lines.append("")
                lines.append(contentsOf: render(row: row, index: index, assets: &assets, label: label))
            }
        }

        let allowedNodes: Set<NodeID>? = routeTitle == nil
            ? nil
            : Set(outlines.flatMap(\.rows).map(\.nodeID))
        let threads = project.threads.filter { thread in
            guard let allowedNodes else { return true }
            return thread.entries.contains { allowedNodes.contains($0.nodeID) }
        }
        if !threads.isEmpty {
            lines.append("")
            lines.append("## \(label("线索"))")
            for thread in threads {
                lines.append("")
                lines.append("### \(label(thread.kind.displayName)) · \(thread.name)")
                for point in ThreadSpine.points(for: thread, in: project) {
                    if let allowedNodes, !allowedNodes.contains(point.entry.nodeID) { continue }
                    let role = label(point.entry.role.displayName)
                    let text = point.entry.text.isEmpty ? "" : "：\(point.entry.text)"
                    lines.append("- \(role)：\(point.chapterTitle) · \(point.node.title)\(text)")
                }
            }
        }

        let ideas = routeTitle == nil ? project.nodes.filter { $0.status == .idea } : []
        if !ideas.isEmpty {
            lines.append("")
            lines.append("## \(label("灵感卡"))")
            for idea in ideas {
                lines.append("")
                lines.append("- \(idea.title)" + (idea.summary.isEmpty ? "" : "：\(idea.summary)"))
            }
        }

        lines.append("")
        return OutlineMarkdownDocument(
            markdown: lines.joined(separator: "\n"),
            assetFileNames: assets.sorted()
        )
    }

    private static func render(row: OutlineRow, index: ProjectIndex, assets: inout Set<String>, label: (String) -> String) -> [String] {
        let pad = String(repeating: "  ", count: row.indent)
        var lines: [String] = []

        if let incoming = row.incoming {
            lines.append("\(pad)> \(incoming.displayText(localize: label))")
        }

        switch row.role {
        case .scene:
            lines.append("\(pad)### \(row.nodeTitle)")
            if row.origin == .detached {
                lines.append("")
                lines.append("\(pad)_\(label("尚未接入故事。"))_")
            }
            if let node = index.nodeByID[row.nodeID] {
                if !node.summary.isEmpty {
                    lines.append("")
                    lines.append("\(pad)\(node.summary)")
                }
                if !node.body.isEmpty {
                    lines.append("")
                    for line in node.body.split(separator: "\n", omittingEmptySubsequences: false) {
                        lines.append("\(pad)\(line)")
                    }
                }
                lines.append(contentsOf: renderFacts(node: node, pad: pad, index: index, assets: &assets, label: label))
            }

        case .revisit:
            lines.append(pad + "↪ " + String(format: label("回到上文「%@」"), row.nodeTitle))

        case .crossChapter:
            let chapterTitle = row.targetChapterID.flatMap { index.chapterByID[$0]?.title } ?? label("另一章")
            lines.append(pad + "→ " + String(format: label("转入 %@「%@」"), chapterTitle, row.nodeTitle))
        }

        return lines
    }

    private static func renderFacts(
        node: StoryNode,
        pad: String,
        index: ProjectIndex,
        assets: inout Set<String>,
        label: (String) -> String
    ) -> [String] {
        var lines: [String] = []
        let characterNames = node.characterIDs.compactMap { index.characterByID[$0]?.name }
        if !characterNames.isEmpty {
            lines.append("")
            lines.append("\(pad)- \(label("出场"))：\(characterNames.joined(separator: "、"))")
        }
        let placeNames = node.placeIDs.compactMap { index.placeByID[$0]?.name }
        if !placeNames.isEmpty {
            lines.append("\(pad)- \(label("地点"))：\(placeNames.joined(separator: "、"))")
        }
        let settingTitles = node.settingIDs.compactMap { index.settingByID[$0]?.title }
        if !settingTitles.isEmpty {
            lines.append("\(pad)- \(label("事实设定"))：\(settingTitles.joined(separator: "、"))")
        }
        if let assetID = node.coverAssetID, let asset = index.assetByID[assetID] {
            let caption = asset.caption.isEmpty ? asset.fileName : asset.caption
            assets.insert(asset.fileName)
            lines.append("\(pad)- \(label("配图"))：![\(caption)](assets/\(asset.fileName))")
        }
        if !node.annotation.isEmpty {
            lines.append("\(pad)- \(label("注释"))：\(node.annotation)")
        }
        return lines
    }
}
