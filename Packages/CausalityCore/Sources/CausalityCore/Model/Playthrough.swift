import Foundation

/// 试玩时一个可选去向。
public struct PlaythroughOption: Identifiable, Sendable, Hashable {
    public var edgeID: EdgeID
    public var kind: EdgeKind
    public var label: String
    public var condition: String
    public var targetID: NodeID
    public var targetTitle: String
    public var targetChapterTitle: String

    public var id: EdgeID { edgeID }
}

/// 试玩历史里的一步。
public struct PlaythroughStep: Identifiable, Sendable, Equatable {
    public var node: StoryNode
    public var incomingEdgeID: EdgeID?
    public var incomingLabel: String?
    public var options: [PlaythroughOption]
    public var cumulativeWords: Int
    public var stepNumber: Int

    public var id: NodeID { node.id }
}

public struct PlaythroughVisit: Sendable, Equatable {
    public var nodeID: NodeID
    public var incomingEdgeID: EdgeID?

    public init(nodeID: NodeID, incomingEdgeID: EdgeID? = nil) {
        self.nodeID = nodeID
        self.incomingEdgeID = incomingEdgeID
    }
}

/// 一条正在走的路。只读推导，不写回工程。
public struct Playthrough: Sendable, Equatable {
    public var visits: [PlaythroughVisit]
    public var steps: [PlaythroughStep]
    public var finished: Bool
    public var deadEnd: Bool
    public var cumulativeWords: Int

    public var current: PlaythroughStep? { steps.last }
    public var stepCount: Int { steps.count }
}

public enum PlaythroughEngine {
    public static func start(in project: StoryProject) -> Playthrough? {
        let index = project.makeIndex()
        var starts = project.nodes.filter(\.isEntry).map(\.id)
        if starts.isEmpty, let firstChapter = project.chapters.first {
            starts = index.nodes(in: firstChapter.id).filter { $0.status == .draft }.prefix(1).map(\.id)
        }
        guard let start = starts.first(where: { index.nodeByID[$0]?.status == .draft }) else { return nil }
        return build(visits: [PlaythroughVisit(nodeID: start)], project: project)
    }

    public static func choose(
        _ edgeID: EdgeID,
        in playthrough: Playthrough,
        project: StoryProject
    ) -> Playthrough? {
        guard let current = playthrough.current,
              current.options.contains(where: { $0.edgeID == edgeID }),
              let option = current.options.first(where: { $0.edgeID == edgeID }) else {
            return nil
        }
        var visits = playthrough.visits
        visits.append(PlaythroughVisit(nodeID: option.targetID, incomingEdgeID: edgeID))
        return build(visits: visits, project: project)
    }

    public static func back(_ playthrough: Playthrough, project: StoryProject) -> Playthrough? {
        guard playthrough.visits.count > 1 else { return playthrough }
        return build(visits: Array(playthrough.visits.dropLast()), project: project)
    }

    /// 面包屑跳回第 index 步（0-based），后面的步骤丢掉。
    public static func jump(
        to index: Int,
        in playthrough: Playthrough,
        project: StoryProject
    ) -> Playthrough? {
        guard index >= 0, index < playthrough.visits.count else { return nil }
        return build(visits: Array(playthrough.visits.prefix(index + 1)), project: project)
    }

    private static func build(visits: [PlaythroughVisit], project: StoryProject) -> Playthrough? {
        let index = project.makeIndex()
        var steps: [PlaythroughStep] = []
        var total = 0
        for (offset, visit) in visits.enumerated() {
            guard let node = index.nodeByID[visit.nodeID], node.status == .draft else { return nil }
            total += WordCount.count(of: node)
            let incoming = visit.incomingEdgeID.flatMap { project.edge($0) }
            let options = index.outgoingEdges(of: node.id).compactMap { edge -> PlaythroughOption? in
                guard let target = index.nodeByID[edge.to], target.status == .draft else { return nil }
                return PlaythroughOption(
                    edgeID: edge.id,
                    kind: edge.kind,
                    label: edge.label.isEmpty ? edge.kind.displayName : edge.label,
                    condition: edge.condition,
                    targetID: edge.to,
                    targetTitle: target.title,
                    targetChapterTitle: target.chapterID.flatMap { index.chapterByID[$0]?.title } ?? "未分章"
                )
            }
            steps.append(
                PlaythroughStep(
                    node: node,
                    incomingEdgeID: visit.incomingEdgeID,
                    incomingLabel: incoming?.label.isEmpty == false ? incoming?.label : incoming?.kind.displayName,
                    options: options,
                    cumulativeWords: total,
                    stepNumber: offset + 1
                )
            )
        }
        guard let current = steps.last else { return nil }
        let finished = current.node.kind == .ending
        return Playthrough(
            visits: visits,
            steps: steps,
            finished: finished,
            deadEnd: !finished && current.options.isEmpty,
            cumulativeWords: total
        )
    }
}
