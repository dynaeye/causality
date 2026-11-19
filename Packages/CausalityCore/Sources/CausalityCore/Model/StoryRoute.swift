import Foundation

/// 通往某个结局的全部路径。
///
/// 「只看通往某个结局的路径」和单路线 Markdown 导出共用这一份推导：
/// 先从入口向前走一遍，再从结局向后走一遍，两边都到得了的节点才在这条路上。
public struct StoryRoute: Sendable, Equatable {
    public var endingID: NodeID
    public var nodeIDs: Set<NodeID>
    public var edgeIDs: Set<EdgeID>

    public init(endingID: NodeID, nodeIDs: Set<NodeID> = [], edgeIDs: Set<EdgeID> = []) {
        self.endingID = endingID
        self.nodeIDs = nodeIDs
        self.edgeIDs = edgeIDs
    }

    public var isEmpty: Bool { nodeIDs.isEmpty }

    /// 从入口到 `endingID` 的所有路径，合并成一张子图。
    public static func paths(to endingID: NodeID, in project: StoryProject) -> StoryRoute {
        let index = project.makeIndex()
        guard index.nodeByID[endingID] != nil else {
            return StoryRoute(endingID: endingID)
        }

        var starts = project.nodes.filter(\.isEntry).map(\.id)
        if starts.isEmpty, let firstChapter = project.chapters.first {
            starts = index.nodes(in: firstChapter.id).prefix(1).map(\.id)
        }
        guard !starts.isEmpty else { return StoryRoute(endingID: endingID) }

        let forward = reachable(from: starts, in: index, outgoing: true)
        let backward = reachable(from: [endingID], in: index, outgoing: false)

        let nodes = forward.intersection(backward)
        let edges = Set(project.edges.filter { edge in
            nodes.contains(edge.from) && nodes.contains(edge.to)
        }.map(\.id))
        return StoryRoute(endingID: endingID, nodeIDs: nodes, edgeIDs: edges)
    }

    /// 从一组起点沿出边或入边走，遇到已访问的就停。
    private static func reachable(
        from starts: [NodeID],
        in index: ProjectIndex,
        outgoing: Bool
    ) -> Set<NodeID> {
        var seen: Set<NodeID> = []
        var queue = starts
        while let id = queue.popLast() {
            guard seen.insert(id).inserted else { continue }
            let next = outgoing
                ? index.outgoingEdges(of: id).map(\.to)
                : index.incomingEdges(of: id).map(\.from)
            queue.append(contentsOf: next)
        }
        return seen
    }
}
