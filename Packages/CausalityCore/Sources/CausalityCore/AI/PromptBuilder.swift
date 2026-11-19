import Foundation

public enum AIRequestKind: String, Codable, Sendable, CaseIterable {
    /// 自由讨论：只写进对话记录，不产生提案。
    case discussion
    /// 整理成大纲：把已有共识整理为场景与连线。
    case outline
    /// 修改选中内容：最小改动，其它分支与结局保持原样。
    case editSelection
    /// 在故事板的某个缝隙里补一张卡。
    case insertCard

    public var displayName: String {
        switch self {
        case .discussion: "讨论"
        case .outline: "整理成大纲"
        case .editSelection: "修改选中内容"
        case .insertCard: "在这里插一张卡"
        }
    }

    public var producesProposal: Bool { self != .discussion }
}

public enum AIContextScope: String, Codable, Sendable, CaseIterable {
    case selection
    case chapter
    case project

    public var displayName: String {
        switch self {
        case .selection: "选中项与相邻"
        case .chapter: "本章"
        case .project: "全书"
        }
    }
}

/// 本轮真正发给模型的材料。界面上的“引用了哪些材料”也读它。
public struct AIContext: Sendable {
    public struct Reference: Identifiable, Sendable, Hashable {
        public enum Kind: String, Sendable {
            case node, edge, setting, character, place, asset, chapter
        }

        public var kind: Kind
        public var rawID: UUID
        public var title: String

        public var id: String { "\(kind.rawValue):\(rawID.uuidString)" }
    }

    public var projectTitle: String
    public var logline: String
    public var settings: [Setting]
    public var nodes: [StoryNode]
    public var edges: [StoryEdge]
    public var characters: [StoryCharacter]
    public var places: [StoryPlace]
    /// 配图默认只发说明文字，原图要作者单独选中。
    public var assetCaptions: [String]
    public var selection: NodeID?
    /// 故事板上这一轮要插卡的位置。
    public var insertionAnchorTitle: String?
    public var insertionChapterTitle: String?
    public var references: [Reference]

    public var referenceIDs: Set<String> { Set(references.map(\.id)) }
}

public enum PromptBuilder {
    public static func makeContext(
        kind: AIRequestKind,
        contextScope: AIContextScope,
        selection: NodeID?,
        project: StoryProject,
        insertion: CardInsertionPoint? = nil,
        excluded: Set<String> = []
    ) -> AIContext {
        let picked = pick(contextScope: contextScope, selection: selection, project: project)
        var context = assemble(
            contextScope: contextScope,
            selection: selection,
            project: project,
            nodeIDs: picked.nodes,
            edgeIDs: picked.edges,
            chapterIDs: picked.chapters,
            excluded: excluded
        )
        if let insertion {
            context.insertionAnchorTitle = insertion.anchorNodeID.flatMap { project.node($0)?.title }
            context.insertionChapterTitle = project.chapter(insertion.chapterID)?.title
        }
        return context
    }

    /// 按范围挑出要发出去的节点、连线与章节。
    private static func pick(
        contextScope: AIContextScope,
        selection: NodeID?,
        project: StoryProject
    ) -> (nodes: Set<NodeID>, edges: Set<EdgeID>, chapters: Set<ChapterID>) {
        let index = project.makeIndex()
        var nodes: Set<NodeID> = []
        var edges: Set<EdgeID> = []
        var chapters: Set<ChapterID> = []

        switch contextScope {
        case .selection:
            guard let selection, index.nodeByID[selection] != nil else {
                return (nodes, edges, chapters)
            }
            nodes.insert(selection)
            for edge in index.outgoingEdges(of: selection) {
                edges.insert(edge.id)
                nodes.insert(edge.to)
            }
            for edge in index.incomingEdges(of: selection) {
                edges.insert(edge.id)
                nodes.insert(edge.from)
            }
            if let chapterID = index.nodeByID[selection]?.chapterID {
                chapters.insert(chapterID)
            }

        case .chapter:
            let chapterID = selection.flatMap { index.nodeByID[$0]?.chapterID } ?? project.chapters.first?.id
            if let chapterID {
                chapters.insert(chapterID)
                for node in project.nodes where node.chapterID == chapterID {
                    nodes.insert(node.id)
                }
                for edge in project.edges where nodes.contains(edge.from) || nodes.contains(edge.to) {
                    edges.insert(edge.id)
                }
            }

        case .project:
            chapters = Set(project.chapters.map(\.id))
            nodes = Set(project.nodes.map(\.id))
            edges = Set(project.edges.map(\.id))
        }

        return (nodes, edges, chapters)
    }

    private static func assemble(
        contextScope: AIContextScope,
        selection: NodeID?,
        project: StoryProject,
        nodeIDs: Set<NodeID>,
        edgeIDs: Set<EdgeID>,
        chapterIDs: Set<ChapterID>,
        excluded: Set<String>
    ) -> AIContext {
        // 作者在输入区移除的引用，同时从材料里拿掉。
        let excludedNodeIDs = Set(
            nodeIDs.filter { excluded.contains("node:\($0.rawValue.uuidString)") }
        )
        let nodes = project.nodes.filter { nodeIDs.contains($0.id) && !excludedNodeIDs.contains($0.id) }
        let edges = project.edges.filter { edge in
            edgeIDs.contains(edge.id)
                && !excluded.contains("edge:\(edge.id.rawValue.uuidString)")
                && !excludedNodeIDs.contains(edge.from)
                && !excludedNodeIDs.contains(edge.to)
        }
        let characters = project.characters.filter { character in
            !excluded.contains("character:\(character.id.rawValue.uuidString)")
                && nodes.contains { $0.characterIDs.contains(character.id) }
        }
        let places = project.places.filter { place in
            !excluded.contains("place:\(place.id.rawValue.uuidString)")
                && nodes.contains { $0.placeIDs.contains(place.id) }
        }
        // 默认发送本轮相关且已确认的设定，锁定项也在其中，因为它们是既定事实。
        let settings = project.settings.filter { setting in
            !excluded.contains("setting:\(setting.id.rawValue.uuidString)")
                && setting.isConfirmed
                && (nodes.contains { $0.settingIDs.contains(setting.id) }
                    || setting.attachedNodeIDs.contains { nodeIDs.contains($0) })
        }
        let captions = nodes.compactMap { node -> String? in
            guard let assetID = node.coverAssetID, let asset = project.asset(assetID) else { return nil }
            let caption = asset.caption.isEmpty ? asset.fileName : asset.caption
            return "\(node.title)：\(caption)"
        }

        let chapters = chapterIDs.compactMap { project.chapter($0) }
        let references = buildReferences(
            ReferenceInputs(
                nodes: nodes,
                edges: edges,
                settings: settings,
                characters: characters,
                places: places,
                chapters: chapters
            ),
            excluded: excluded
        )

        return AIContext(
            projectTitle: project.title,
            logline: project.logline,
            settings: settings,
            nodes: nodes,
            edges: edges,
            characters: characters,
            places: places,
            assetCaptions: captions,
            selection: selection,
            references: references
        )
    }

    struct ReferenceInputs {
        var nodes: [StoryNode]
        var edges: [StoryEdge]
        var settings: [Setting]
        var characters: [StoryCharacter]
        var places: [StoryPlace]
        var chapters: [Chapter]
    }

    private static func buildReferences(
        _ inputs: ReferenceInputs,
        excluded: Set<String>
    ) -> [AIContext.Reference] {
        var references: [AIContext.Reference] = []
        references += inputs.nodes.map { .init(kind: .node, rawID: $0.id.rawValue, title: $0.title) }
        references += inputs.edges.map { edge in
            .init(kind: .edge, rawID: edge.id.rawValue, title: edge.label.isEmpty ? edge.kind.displayName : edge.label)
        }
        references += inputs.settings.map { .init(kind: .setting, rawID: $0.id.rawValue, title: $0.title) }
        references += inputs.characters.map { .init(kind: .character, rawID: $0.id.rawValue, title: $0.name) }
        references += inputs.places.map { .init(kind: .place, rawID: $0.id.rawValue, title: $0.name) }
        references += inputs.chapters.map { .init(kind: .chapter, rawID: $0.id.rawValue, title: $0.title) }
        return references.filter { !excluded.contains($0.id) }
    }

    /// 给没有严格结构化输出的服务用的字段示例。模型照着抄，解析就能过。
    static func schemaHint(localize: (String) -> String) -> String {
        let placeholder = localize("n1 或场景 UUID")
        let sceneID = localize("场景 UUID")
        return """
        {"summary":"\(localize("一句话说明这次改什么"))",
         "nodes":[{"ref":"n1","title":"","kind":"event","summary":"","body":"","characterNames":[],"placeNames":[],"settingTitles":[],"afterRef":null}],
         "edges":[{"from":"\(placeholder)","to":"\(placeholder)","kind":"cause","label":"","condition":""}],
         "changes":[{"target":"node","id":"\(sceneID)","title":null,"summary":null,"body":null,"nodeKind":null,"label":null,"condition":null,"edgeKind":null,"text":null}],
         "removals":[{"target":"node","id":"\(sceneID)"}],
         "notes":[""]}
        \(localize("kind 取值 event/choice/ending；edgeKind 取值 cause/choice/condition/plain；changes 里只填要改的字段，其余保持 null。"))
        """
    }

    public static func systemPrompt(
        for kind: AIRequestKind,
        localize: (String) -> String = { $0 }
    ) -> String {
        var lines: [String] = [
            localize("你是「因果」的故事策划助手，服务一位独自写分支故事的作者。"),
            localize("讨论使用作者提问的语言。创作或改写正文时沿用作品语言，除非作者明确指定其他语言。具体、可写、少形容词。你已经看到作者的项目材料，直接用它，不要反问已知信息。")
        ]
        switch kind {
        case .discussion:
            lines.append(localize("这一轮只讨论，不改动项目。给出判断、取舍和下一步建议，必要时指出还没决定的问题。"))
            lines.append(localize("不要输出 JSON，也不要列出你“建议添加”的字段格式。"))
        case .outline:
            lines.append(localize("把已有共识整理成场景与连线，输出一份提案 JSON，不要输出 JSON 以外的任何文字。"))
            lines.append(localize("只新增或补全作者已经表达过的内容；还没决定的事情写进 notes，不要编造成既定事实。"))
        case .editSelection:
            lines.append(localize("只改动与选中项相关的最小范围，输出一份提案 JSON，不要输出 JSON 以外的任何文字。"))
            lines.append(localize("其它分支、汇合点和结局保持原样；如果你认为它们也需要改，写进 notes 说明理由。"))
            lines.append(localize("选项原文与原因保留在连线上，场景正文只写这个场景本身。"))
        case .insertCard:
            lines.append(localize("作者已经指着故事板上的一处缝隙。只新增一张卡，输出一份提案 JSON，不要输出 JSON 以外的任何文字。"))
            lines.append(localize("这张卡先是一句念头也可以：写清它此刻让人想到什么，不要替作者把后面几场戏一起写了。"))
            lines.append(localize("除非作者明确要求，否则不要改动已有卡片。"))
        }
        lines.append(localize("nodeKind 只能是 event、choice、ending；edgeKind 只能是 cause、choice、condition、plain。"))
        lines.append(localize("标着「灵感卡」的节点还躺在故事板上，没进大纲；除非作者明确要求，不要把灵感卡当成定稿场景改。"))
        lines.append(localize("新增节点用 ref 标识（例如 n_ferry），新增连线用 ref 或已有节点 UUID 作为端点。"))
        return lines.joined(separator: "\n")
    }

    public static func userMessage(
        kind: AIRequestKind,
        context: AIContext,
        instruction: String,
        localize: (String) -> String = { $0 }
    ) -> String {
        var lines: [String] = [String(format: localize("【项目】%@"), context.projectTitle)]
        if !context.logline.isEmpty {
            lines.append(String(format: localize("梗概：%@"), context.logline))
        }
        lines.append(contentsOf: settingsSection(context, localize: localize))
        lines.append(contentsOf: nodesSection(context, localize: localize))
        lines.append(contentsOf: edgesSection(context, localize: localize))
        lines.append(contentsOf: castSection(context, localize: localize))
        lines.append(contentsOf: captionsSection(context, localize: localize))
        if let chapter = context.insertionChapterTitle {
            lines.append("")
            lines.append(String(format: localize("【插入位置】%@"), chapter))
            if let anchor = context.insertionAnchorTitle {
                lines.append(String(format: localize("新卡插在「%@」之后。"), anchor))
            } else {
                lines.append(localize("新卡插在这一章的开头。"))
            }
        }

        lines.append("")
        lines.append(localize("【作者这一轮的要求】"))
        lines.append(instruction)
        if kind.producesProposal {
            lines.append("")
            lines.append(localize("只输出一个 JSON 对象，字段名必须与下面完全一致，不要加别的键："))
            lines.append(Self.schemaHint(localize: localize))
            if kind == .editSelection {
                lines.append(localize("改动尽量少：只改这一个场景和与它直接相关的连线。"))
            }
        }
        return lines.joined(separator: "\n")
    }
}
