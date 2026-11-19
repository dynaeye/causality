import Foundation

/// 从某张卡出发还能走到哪些结局。只读，用来回答「这段之后还有什么」。
public struct ReachableEnding: Sendable, Equatable, Identifiable {
    public var endingID: NodeID
    public var title: String
    /// 最少几步到（按边数算）。
    public var steps: Int
    /// 是否在主线上。
    public var onMainline: Bool

    public var id: NodeID { endingID }

    public init(endingID: NodeID, title: String, steps: Int, onMainline: Bool) {
        self.endingID = endingID
        self.title = title
        self.steps = steps
        self.onMainline = onMainline
    }
}

public enum EndingReach {
    /// 从 `nodeID` 沿出边走，BFS 记录到每个结局的最短步数。结局不再往后穿。
    public static func from(_ nodeID: NodeID, in project: StoryProject) -> [ReachableEnding] {
        let index = project.makeIndex()
        guard index.nodeByID[nodeID] != nil else { return [] }
        let mainline = Mainline.derive(in: project)

        var steps: [NodeID: Int] = [nodeID: 0]
        var queue: [NodeID] = [nodeID]
        var found: [(NodeID, Int)] = []

        while !queue.isEmpty {
            let current = queue.removeFirst()
            let depth = steps[current] ?? 0
            guard let node = index.nodeByID[current] else { continue }
            if node.kind == .ending {
                found.append((current, depth))
                continue
            }
            for edge in index.outgoingEdges(of: current) where steps[edge.to] == nil {
                steps[edge.to] = depth + 1
                queue.append(edge.to)
            }
        }

        return found
            .map { id, depth in
                ReachableEnding(
                    endingID: id,
                    title: index.nodeByID[id]?.title ?? "结局",
                    steps: depth,
                    onMainline: mainline.contains(node: id)
                )
            }
            .sorted { ($0.steps, $0.title) < ($1.steps, $1.title) }
    }
}
