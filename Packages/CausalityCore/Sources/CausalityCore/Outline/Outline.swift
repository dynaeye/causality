import Foundation

/// 一条通往本行的连线。选项原文、原因、条件都在这里，界面与导出共用。
public struct OutlineIncomingEdge: Sendable, Hashable {
    public let edgeID: EdgeID
    public let from: NodeID
    public let kind: EdgeKind
    public let label: String
    public let condition: String

    public init(edge: StoryEdge) {
        self.edgeID = edge.id
        self.from = edge.from
        self.kind = edge.kind
        self.label = edge.label
        self.condition = edge.condition
    }

    /// 例如「选项：阿禾答应替寄信人守密」。
    public var displayText: String {
        displayText(localize: { $0 })
    }

    public func displayText(localize: (String) -> String) -> String {
        let kindName = localize(kind.displayName)
        let head = label.isEmpty ? kindName : kindName + localize("：") + label
        guard !condition.isEmpty else { return head }
        return head + String(format: localize("（%@）"), localize("条件") + localize("：") + condition)
    }
}

/// 大纲的一行。正文只在首次到达时占一行，再次到达是跳转行。
public struct OutlineRow: Identifiable, Sendable, Hashable {
    public enum Role: String, Sendable, Hashable {
        /// 首次到达，展示正文。
        case scene
        /// 汇合或回环处的再次到达，显示跳转。
        case revisit
        /// 指向另一章的节点，本章只显示跳转。
        case crossChapter
    }

    public enum Origin: String, Sendable, Hashable {
        /// 章节入口。
        case entry
        /// 由上一条发展线到达。
        case edge
        /// 遍历完入口后补上的未接线节点。
        case detached
    }

    public let id: Int
    public let nodeID: NodeID
    public let nodeTitle: String
    public let nodeKind: NodeKind
    public let role: Role
    public let indent: Int
    public let origin: Origin
    public let incoming: OutlineIncomingEdge?
    public let targetChapterID: ChapterID?

    public var isScene: Bool { role == .scene }
}

public struct ChapterOutline: Identifiable, Sendable, Hashable {
    public let chapterID: ChapterID
    public let chapterTitle: String
    public let chapterSummary: String
    public let rows: [OutlineRow]

    public var id: ChapterID { chapterID }

    /// 只留这条路上的行，用来「只看通往某个结局的路径」。
    public func filtered(to nodes: Set<NodeID>) -> ChapterOutline {
        ChapterOutline(
            chapterID: chapterID,
            chapterTitle: chapterTitle,
            chapterSummary: chapterSummary,
            rows: rows.filter { nodes.contains($0.nodeID) }
        )
    }
    public var sceneCount: Int { rows.count { $0.role == .scene } }
    public var revisitCount: Int { rows.count { $0.role == .revisit } }
    public var crossChapterCount: Int { rows.count { $0.role == .crossChapter } }
    public var detachedCount: Int { rows.count { $0.role == .scene && $0.origin == .detached } }
}

/// 大纲推导。界面与 Markdown 导出共用同一套规则。
///
/// 规则：
/// 1. 章内顺序表给出同级顺序与入口顺序；没有标入口时取顺序表第一项当入口。
/// 2. 从入口做首次访问 DFS。
/// 3. 线性剧情保持同级，只有出边多于一条时才增加缩进。
/// 4. 首次到达展示正文，再次到达显示跳转，跨章到达显示跨章跳转。
/// 5. 遍历完入口后，补上本章尚未访问到的节点。
public enum OutlineBuilder {
    public static func build(project: StoryProject) -> [ChapterOutline] {
        build(project: project, index: project.makeIndex())
    }

    public static func build(project: StoryProject, index: ProjectIndex) -> [ChapterOutline] {
        build(project: project, index: index, nodes: nil)
    }

    /// `nodes` 给了就只走这些节点，用来只看通往某个结局的路径。
    public static func build(
        project: StoryProject,
        index: ProjectIndex,
        nodes: Set<NodeID>?
    ) -> [ChapterOutline] {
        project.chapters.map { chapter in
            var walk = ChapterWalk(project: project, index: index, chapter: chapter, filter: nodes)
            return walk.run()
        }
    }
}

private struct ChapterWalk {
    let project: StoryProject
    let index: ProjectIndex
    let chapter: Chapter
    private let orders: [NodeID: Int]
    /// 只看这条路时，范围外的节点直接不进大纲。
    private let filter: Set<NodeID>?

    private var visited: Set<NodeID> = []
    private var rows: [OutlineRow] = []
    private var nextRowID = 0

    init(project: StoryProject, index: ProjectIndex, chapter: Chapter, filter: Set<NodeID>? = nil) {
        self.project = project
        self.index = index
        self.chapter = chapter
        self.filter = filter
        var orders: [NodeID: Int] = [:]
        for (offset, nodeID) in chapter.order.enumerated() where orders[nodeID] == nil {
            orders[nodeID] = offset
        }
        self.orders = orders
    }

    mutating func run() -> ChapterOutline {
        // 故事板上的念头先留在板上，写成正式场景后才进大纲。
        let chapterNodes = index.nodes(in: chapter.id).filter { node in
            node.status == .draft && (filter?.contains(node.id) ?? true)
        }
        let entries = chapterNodes.filter(\.isEntry)
        let starts = entries.isEmpty ? Array(chapterNodes.prefix(1)) : entries

        for entry in starts {
            walk(nodeID: entry.id, indent: 0, incoming: nil, origin: .entry)
        }

        for node in chapterNodes where !visited.contains(node.id) {
            walk(nodeID: node.id, indent: 0, incoming: nil, origin: .detached)
        }

        return ChapterOutline(
            chapterID: chapter.id,
            chapterTitle: chapter.title,
            chapterSummary: chapter.summary,
            rows: rows
        )
    }

    private mutating func walk(
        nodeID: NodeID,
        indent: Int,
        incoming: OutlineIncomingEdge?,
        origin: OutlineRow.Origin
    ) {
        guard let node = index.nodeByID[nodeID] else { return }

        if node.chapterID != chapter.id {
            appendRow(node, role: .crossChapter, indent: indent, origin: origin, incoming: incoming)
            return
        }

        if visited.contains(nodeID) {
            appendRow(node, role: .revisit, indent: indent, origin: origin, incoming: incoming)
            return
        }

        visited.insert(nodeID)
        appendRow(node, role: .scene, indent: indent, origin: origin, incoming: incoming)

        let edges = sortedOutgoingEdges(of: nodeID)
        guard !edges.isEmpty else { return }
        let indentStep = edges.count > 1 ? 1 : 0
        for edge in edges {
            walk(
                nodeID: edge.to,
                indent: indent + indentStep,
                incoming: OutlineIncomingEdge(edge: edge),
                origin: .edge
            )
        }
    }

    private mutating func appendRow(
        _ node: StoryNode,
        role: OutlineRow.Role,
        indent: Int,
        origin: OutlineRow.Origin,
        incoming: OutlineIncomingEdge?
    ) {
        rows.append(
            OutlineRow(
                id: nextRowID,
                nodeID: node.id,
                nodeTitle: node.title,
                nodeKind: node.kind,
                role: role,
                indent: indent,
                origin: origin,
                incoming: incoming,
                targetChapterID: role == .crossChapter ? node.chapterID : nil
            )
        )
        nextRowID += 1
    }

    /// 并列分支按章内顺序表排列，保证每次推导结果一致。
    private func sortedOutgoingEdges(of nodeID: NodeID) -> [StoryEdge] {
        index.outgoingEdges(of: nodeID).sorted { lhs, rhs in
            let leftOrder = index.nodeByID[lhs.to]?.chapterID == chapter.id ? (orders[lhs.to] ?? Int.max) : Int.max
            let rightOrder = index.nodeByID[rhs.to]?.chapterID == chapter.id ? (orders[rhs.to] ?? Int.max) : Int.max
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            if lhs.label != rhs.label { return lhs.label < rhs.label }
            return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
        }
    }
}
