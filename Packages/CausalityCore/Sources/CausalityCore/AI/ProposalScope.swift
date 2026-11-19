import Foundation

/// 故事板上的一个缝隙：哪一章、第几张之前。
public struct CardInsertionPoint: Sendable, Hashable {
    public var chapterID: ChapterID
    public var index: Int
    public var anchorNodeID: NodeID?

    public init(chapterID: ChapterID, index: Int, anchorNodeID: NodeID? = nil) {
        self.chapterID = chapterID
        self.index = index
        self.anchorNodeID = anchorNodeID
    }
}

/// 提案允许改动到哪里。范围外的改动只作讨论建议。
public struct ProposalScope: Sendable, Equatable {
    public var editableNodeIDs: Set<NodeID>
    public var editableEdgeIDs: Set<EdgeID>
    public var editableSettingIDs: Set<SettingID>
    public var allowNewNodes: Bool
    public var allowNewEdges: Bool
    public var allowRemovals: Bool
    /// 新节点落在哪一章。
    public var defaultChapterID: ChapterID?
    /// AI 没写位置时，新卡插在这张卡之后。
    public var defaultInsertAfter: NodeID?
    /// 没有锚点卡时（例如插在章首），新卡落在章内这个位置。
    public var defaultInsertIndex: Int?

    public init(
        editableNodeIDs: Set<NodeID> = [],
        editableEdgeIDs: Set<EdgeID> = [],
        editableSettingIDs: Set<SettingID> = [],
        allowNewNodes: Bool = true,
        allowNewEdges: Bool = true,
        allowRemovals: Bool = false,
        defaultChapterID: ChapterID? = nil,
        defaultInsertAfter: NodeID? = nil,
        defaultInsertIndex: Int? = nil
    ) {
        self.editableNodeIDs = editableNodeIDs
        self.editableEdgeIDs = editableEdgeIDs
        self.editableSettingIDs = editableSettingIDs
        self.allowNewNodes = allowNewNodes
        self.allowNewEdges = allowNewEdges
        self.allowRemovals = allowRemovals
        self.defaultChapterID = defaultChapterID
        self.defaultInsertAfter = defaultInsertAfter
        self.defaultInsertIndex = defaultInsertIndex
    }

    public func contains(nodeID: NodeID) -> Bool { editableNodeIDs.contains(nodeID) }

    public func contains(edgeID: EdgeID) -> Bool { editableEdgeIDs.contains(edgeID) }

    public func contains(settingID: SettingID) -> Bool { editableSettingIDs.contains(settingID) }

    /// 从选中节点出发：节点本身、它的一跳邻居、以及它们之间的连线。
    public static func selection(
        nodeID: NodeID,
        in project: StoryProject,
        expandNeighbors: Bool = true
    ) -> ProposalScope {
        let index = project.makeIndex()
        guard let node = index.nodeByID[nodeID] else {
            return ProposalScope(defaultChapterID: project.chapters.first?.id)
        }

        var nodes: Set<NodeID> = [nodeID]
        var edges: Set<EdgeID> = []
        for edge in index.outgoingEdges(of: nodeID) {
            if expandNeighbors { nodes.insert(edge.to) }
            edges.insert(edge.id)
        }
        for edge in index.incomingEdges(of: nodeID) {
            if expandNeighbors { nodes.insert(edge.from) }
            edges.insert(edge.id)
        }

        // 相邻节点之间的连线一并纳入范围，避免“只改一条分支却被判超范围”。
        let nodeIDs = nodes
        for edge in project.edges where nodeIDs.contains(edge.from) && nodeIDs.contains(edge.to) {
            edges.insert(edge.id)
        }

        let settings = Set(project.settings.filter { !$0.isLocked }.map(\.id))

        return ProposalScope(
            editableNodeIDs: nodes,
            editableEdgeIDs: edges,
            editableSettingIDs: settings,
            allowNewNodes: true,
            allowNewEdges: true,
            allowRemovals: false,
            defaultChapterID: node.chapterID ?? project.chapters.first?.id
        )
    }

    /// 整章范围。
    public static func chapter(_ chapterID: ChapterID, in project: StoryProject) -> ProposalScope {
        let nodeIDs = Set(project.nodes.filter { $0.chapterID == chapterID }.map(\.id))
        let edgeIDs = Set(project.edges.filter { nodeIDs.contains($0.from) && nodeIDs.contains($0.to) }.map(\.id))
        return ProposalScope(
            editableNodeIDs: nodeIDs,
            editableEdgeIDs: edgeIDs,
            editableSettingIDs: Set(project.settings.filter { !$0.isLocked }.map(\.id)),
            allowNewNodes: true,
            allowNewEdges: true,
            allowRemovals: false,
            defaultChapterID: chapterID
        )
    }

    /// 故事板上“这里”的范围：某一章的某一个缝隙。
    public static func insertion(
        chapterID: ChapterID,
        index: Int,
        in project: StoryProject
    ) -> ProposalScope {
        guard let chapter = project.chapter(chapterID) else {
            return .wholeProject(project)
        }
        let anchor = index > 0 && index <= chapter.order.count ? chapter.order[index - 1] : nil
        var nodes: Set<NodeID> = []
        if let anchor {
            nodes.insert(anchor)
        }
        if index < chapter.order.count {
            nodes.insert(chapter.order[index])
        }
        for edge in project.edges {
            guard nodes.contains(edge.from) || nodes.contains(edge.to) else { continue }
            nodes.insert(edge.from)
            nodes.insert(edge.to)
        }
        let edgeIDs = Set(project.edges.filter { nodes.contains($0.from) && nodes.contains($0.to) }.map(\.id))
        return ProposalScope(
            editableNodeIDs: nodes,
            editableEdgeIDs: edgeIDs,
            editableSettingIDs: Set(project.settings.filter { !$0.isLocked }.map(\.id)),
            allowNewNodes: true,
            allowNewEdges: true,
            allowRemovals: false,
            defaultChapterID: chapterID,
            defaultInsertAfter: anchor,
            defaultInsertIndex: index
        )
    }

    /// 全书范围。作者明确要求时才用。
    public static func wholeProject(_ project: StoryProject) -> ProposalScope {
        ProposalScope(
            editableNodeIDs: Set(project.nodes.map(\.id)),
            editableEdgeIDs: Set(project.edges.map(\.id)),
            editableSettingIDs: Set(project.settings.filter { !$0.isLocked }.map(\.id)),
            allowNewNodes: true,
            allowNewEdges: true,
            allowRemovals: false,
            defaultChapterID: project.chapters.first?.id
        )
    }
}
