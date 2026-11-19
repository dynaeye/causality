import Foundation

/// 写作模式里的一场：章内顺序表上的一个位置。
public struct WritingScene: Identifiable, Sendable, Hashable {
    public let node: StoryNode
    public let chapterID: ChapterID?
    public let chapterTitle: String
    /// 1-based 章号；「未分章」为 0。
    public let chapterNumber: Int
    /// 1-based 章内场次。
    public let sceneNumber: Int

    public var id: NodeID { node.id }

    public init(
        node: StoryNode,
        chapterID: ChapterID?,
        chapterTitle: String,
        chapterNumber: Int,
        sceneNumber: Int
    ) {
        self.node = node
        self.chapterID = chapterID
        self.chapterTitle = chapterTitle
        self.chapterNumber = chapterNumber
        self.sceneNumber = sceneNumber
    }
}

/// 写作模式的线性顺序。与大纲的首次访问 DFS 分开：这里只认 `chapter.order`。
///
/// 契约：
/// 1. 一章一章走 `chapter.order`，每张 draft 恰好出现一次；
/// 2. `order` 里缺的 draft 按 `project.nodes` 的顺序补在章末；
/// 3. 灵感卡不参与；
/// 4. 没有章的 draft 放在最后，章标题写「未分章」。
public enum WritingOrder {
    public static func scenes(in project: StoryProject) -> [WritingScene] {
        var result: [WritingScene] = []
        let nodesOrder = Dictionary(
            uniqueKeysWithValues: project.nodes.enumerated().map { ($0.element.id, $0.offset) }
        )

        for (chapterIndex, chapter) in project.chapters.enumerated() {
            let drafts = project.nodes.filter { $0.chapterID == chapter.id && $0.status == .draft }
            let byID = Dictionary(uniqueKeysWithValues: drafts.map { ($0.id, $0) })
            var seen: Set<NodeID> = []
            var ordered: [StoryNode] = []

            for nodeID in chapter.order {
                guard let node = byID[nodeID], seen.insert(nodeID).inserted else { continue }
                ordered.append(node)
            }
            ordered += drafts
                .filter { !seen.contains($0.id) }
                .sorted { (nodesOrder[$0.id] ?? .max) < (nodesOrder[$1.id] ?? .max) }

            append(ordered, chapter: chapter, number: chapterIndex + 1, to: &result)
        }

        let unassigned = project.nodes
            .filter { $0.status == .draft && $0.chapterID == nil }
            .sorted { (nodesOrder[$0.id] ?? .max) < (nodesOrder[$1.id] ?? .max) }
        for (offset, node) in unassigned.enumerated() {
            result.append(
                WritingScene(
                    node: node,
                    chapterID: nil,
                    chapterTitle: "未分章",
                    chapterNumber: 0,
                    sceneNumber: offset + 1
                )
            )
        }
        return result
    }

    private static func append(
        _ nodes: [StoryNode],
        chapter: Chapter,
        number: Int,
        to result: inout [WritingScene]
    ) {
        for (offset, node) in nodes.enumerated() {
            result.append(
                WritingScene(
                    node: node,
                    chapterID: chapter.id,
                    chapterTitle: chapter.title,
                    chapterNumber: number,
                    sceneNumber: offset + 1
                )
            )
        }
    }
}
