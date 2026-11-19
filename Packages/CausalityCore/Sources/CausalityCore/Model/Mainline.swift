import Foundation

/// 主线：从入口出发、一路沿着作者的“主线去向”走到结局的那串节点与连线。
///
/// 规则：
/// - 每个节点的出边里，带 `isMainline` 的那条就是主线去向。
/// - 一条都没标时，取第一条出边——所以老工程不标注也能直接看出一条主线。
/// - 遇到结局、死路、或者回到走过的节点就停，不会无限展开。
public struct Mainline: Sendable, Equatable {
    public var nodeIDs: Set<NodeID>
    public var edgeIDs: Set<EdgeID>
    /// 这条主线是否来自作者显式标注（全默认取第一条时为 false）。
    public var isExplicit: Bool

    public init(nodeIDs: Set<NodeID> = [], edgeIDs: Set<EdgeID> = [], isExplicit: Bool = false) {
        self.nodeIDs = nodeIDs
        self.edgeIDs = edgeIDs
        self.isExplicit = isExplicit
    }

    public static let empty = Mainline()

    public var isEmpty: Bool { nodeIDs.isEmpty }

    public func contains(node id: NodeID) -> Bool { nodeIDs.contains(id) }
    public func contains(edge id: EdgeID) -> Bool { edgeIDs.contains(id) }

    /// 推导主线。多入口时每个入口各走一遍，合并成一张主线网。
    public static func derive(in project: StoryProject) -> Mainline {
        let index = project.makeIndex()
        var starts = project.nodes.filter(\.isEntry).map(\.id)
        if starts.isEmpty, let firstChapter = project.chapters.first {
            starts = index.nodes(in: firstChapter.id).prefix(1).map(\.id)
        }
        guard !starts.isEmpty else { return .empty }

        var nodeIDs: Set<NodeID> = []
        var edgeIDs: Set<EdgeID> = []
        var explicit = false

        for start in starts {
            var visited: Set<NodeID> = []
            var current: NodeID? = start
            while let id = current, !visited.contains(id) {
                visited.insert(id)
                nodeIDs.insert(id)
                guard let node = index.nodeByID[id], node.kind != .ending else { break }
                let outgoing = index.outgoingEdges(of: id)
                guard let next = chooseEdge(from: outgoing) else { break }
                if next.isMainline { explicit = true }
                edgeIDs.insert(next.id)
                current = next.to
            }
        }
        return Mainline(nodeIDs: nodeIDs, edgeIDs: edgeIDs, isExplicit: explicit)
    }

    /// 标了主线就用标的；没标就按连线顺序取第一条。
    private static func chooseEdge(from outgoing: [StoryEdge]) -> StoryEdge? {
        if let marked = outgoing.first(where: \.isMainline) { return marked }
        return outgoing.first
    }
}
