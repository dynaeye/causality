import Foundation

/// 线索脊柱上的一个点。
public struct ThreadSpinePoint: Identifiable, Sendable, Hashable {
    public var entry: ThreadEntry
    public var node: StoryNode
    public var chapterID: ChapterID?
    public var chapterTitle: String
    public var chapterNumber: Int
    public var orderIndex: Int

    public var id: UUID { entry.id }
}

public enum ThreadSpine {
    /// 按章序与章内顺序表排点；不在章里的点排在最后。
    public static func points(for thread: StoryThread, in project: StoryProject) -> [ThreadSpinePoint] {
        let index = project.makeIndex()
        let nodesOrder = Dictionary(
            uniqueKeysWithValues: project.nodes.enumerated().map { ($0.element.id, $0.offset) }
        )
        var chapterOrder: [NodeID: Int] = [:]
        var chapterOf: [NodeID: ChapterID] = [:]
        var counter = 0
        for chapter in project.chapters {
            for nodeID in chapter.order where chapterOrder[nodeID] == nil {
                chapterOrder[nodeID] = counter
                chapterOf[nodeID] = chapter.id
                counter += 1
            }
        }
        // 章里没进顺序表的节点，按 nodes 顺序补在章末。
        for node in project.nodes where chapterOrder[node.id] == nil {
            chapterOrder[node.id] = counter
            counter += 1
        }

        var points: [ThreadSpinePoint] = []
        for entry in thread.entries {
            guard let node = index.nodeByID[entry.nodeID], node.status == .draft else { continue }
            let chapterID = node.chapterID ?? chapterOf[entry.nodeID]
            let chapter = chapterID.flatMap { index.chapterByID[$0] }
            let chapterNumber = chapterID
                .flatMap { id in project.chapters.firstIndex { $0.id == id } }
                .map { $0 + 1 } ?? 0
            points.append(
                ThreadSpinePoint(
                    entry: entry,
                    node: node,
                    chapterID: chapterID,
                    chapterTitle: chapter?.title ?? "未分章",
                    chapterNumber: chapterNumber,
                    orderIndex: chapterOrder[entry.nodeID] ?? nodesOrder[entry.nodeID] ?? Int.max
                )
            )
        }
        return points.sorted {
            if $0.orderIndex != $1.orderIndex { return $0.orderIndex < $1.orderIndex }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
