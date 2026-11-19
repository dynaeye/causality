import Foundation

/// 规模基准样本：固定种子，覆盖分支汇合、回环、孤立节点与跨章跳转。
public enum BenchmarkFixture {
    public struct Spec: Sendable {
        public var seed: UInt64
        public var nodeCount: Int
        public var edgeCount: Int
        public var chapterCount: Int
        public var orphanCount: Int
        public var cycleEdgeCount: Int
        public var diamondCount: Int
        public var crossChapterEdgeCount: Int

        public init(
            seed: UInt64 = 0x5EED_5EED,
            nodeCount: Int = 500,
            edgeCount: Int = 800,
            chapterCount: Int = 12,
            orphanCount: Int = 6,
            cycleEdgeCount: Int = 4,
            diamondCount: Int = 10,
            crossChapterEdgeCount: Int = 12
        ) {
            self.seed = seed
            self.nodeCount = nodeCount
            self.edgeCount = edgeCount
            self.chapterCount = chapterCount
            self.orphanCount = orphanCount
            self.cycleEdgeCount = cycleEdgeCount
            self.diamondCount = diamondCount
            self.crossChapterEdgeCount = crossChapterEdgeCount
        }
    }

    public struct Facts: Sendable, Equatable {
        public var nodeCount: Int
        public var edgeCount: Int
        public var chapterCount: Int
        public var branchNodes: Int
        public var mergeNodes: Int
        public var crossChapterEdges: Int
        public var cycleEdges: Int
        public var orphanNodes: Int
        public var outlineRowCount: Int
        public var revisitRows: Int
        public var crossChapterRows: Int
        public var detachedRows: Int
    }

    public static func make(spec: Spec = Spec()) -> StoryProject {
        var builder = ProjectBuilder(seed: spec.seed, title: "基准样本", logline: "500 节点 / 800 关系 / 固定种子")
        var random = SplitMix64(seed: spec.seed &+ 17)

        // 第一章由 ProjectBuilder 建好，其余章节补齐。
        var chapters: [ChapterID] = [builder.project.chapters[0].id]
        for _ in 1 ..< spec.chapterCount {
            chapters.append(builder.addChapter(title: "第\(chineseNumeral(chapters.count + 1))章"))
        }

        var nodesByChapter: [[NodeID]] = Array(repeating: [], count: spec.chapterCount)
        var allNodes: [NodeID] = []

        for index in 0 ..< spec.nodeCount {
            let chapterIndex = min(spec.chapterCount - 1, index * spec.chapterCount / spec.nodeCount)
            let isEnding = index % 97 == 96
            let isChoice = index % 23 == 22
            let kind: NodeKind = isEnding ? .ending : (isChoice ? .choice : .event)
            let position = CanvasPoint(
                x: Double(index % 14) * 280,
                y: Double(chapterIndex) * 420 + Double(index % 5) * 90
            )
            let nodeID = builder.addNode(
                title: "场景 \(index + 1)",
                kind: kind,
                summary: "第 \(index + 1) 个场景的一句摘要。",
                body: "第 \(index + 1) 个场景的正文。两三句叙述，用来测量画布与大纲的渲染负担。",
                chapterID: chapters[chapterIndex],
                isEntry: index == 0,
                position: position
            )
            nodesByChapter[chapterIndex].append(nodeID)
            allNodes.append(nodeID)
        }

        // 孤立节点：从链上摘掉，且不参与任何连线。
        var orphanIDs: Set<NodeID> = []
        for step in 0 ..< spec.orphanCount {
            let chapterIndex = (step * 3 + 1) % spec.chapterCount
            guard nodesByChapter[chapterIndex].count > 8 else { continue }
            let pick = nodesByChapter[chapterIndex].remove(at: 5)
            orphanIDs.insert(pick)
        }

        // 主干链：线性剧情。
        var chains: [NodeID] = []
        for chapterNodes in nodesByChapter {
            for position in 0 ..< max(0, chapterNodes.count - 1) where !chains.contains(chapterNodes[position]) {
                builder.connect(chapterNodes[position], to: chapterNodes[position + 1], kind: .plain, label: "接下来")
                chains.append(chapterNodes[position])
            }
        }

        // 分支汇合：跳过一个节点连过去，制造出度 2 与入度 2。
        for step in 0 ..< spec.diamondCount {
            let chapterIndex = (step * 5 + 2) % spec.chapterCount
            let chapterNodes = nodesByChapter[chapterIndex]
            guard chapterNodes.count > 12 else { continue }
            let from = chapterNodes[random.int(in: 1 ... 3)]
            let to = chapterNodes[random.int(in: 8 ... 10)]
            builder.connect(from, to: to, kind: .choice, label: "另一条路")
        }

        // 回环：同章内后面的节点连回前面的节点。
        for step in 0 ..< spec.cycleEdgeCount {
            let chapterIndex = (step * 7 + 3) % spec.chapterCount
            let chapterNodes = nodesByChapter[chapterIndex]
            guard chapterNodes.count > 16 else { continue }
            let from = chapterNodes[chapterNodes.count - 3]
            let to = chapterNodes[6]
            builder.connect(from, to: to, kind: .condition, label: "回访旧地")
        }

        // 跨章跳转。
        for step in 0 ..< spec.crossChapterEdgeCount {
            let chapterIndex = step % max(1, spec.chapterCount - 1)
            let nextIndex = chapterIndex + 1
            guard nextIndex < nodesByChapter.count,
                  let from = nodesByChapter[chapterIndex].last,
                  let to = nodesByChapter[nextIndex].first else { continue }
            builder.connect(from, to: to, kind: .cause, label: "转到下一章")
        }

        // 补足到目标关系数：同章内随机连线，避免重复。
        var attempts = 0
        let pairBudget = 20000
        while builder.project.edges.count < spec.edgeCount && attempts < pairBudget {
            attempts += 1
            let chapterIndex = random.int(in: 0 ... (spec.chapterCount - 1))
            let chapterNodes = nodesByChapter[chapterIndex]
            guard chapterNodes.count > 4 else { continue }
            let fromIndex = random.int(in: 0 ... (chapterNodes.count - 1))
            let toIndex = random.int(in: 0 ... (chapterNodes.count - 1))
            guard fromIndex != toIndex else { continue }
            let from = chapterNodes[fromIndex]
            let to = chapterNodes[toIndex]
            guard !builder.project.edges.contains(where: { $0.from == from && $0.to == to }) else { continue }
            let kind: EdgeKind = random.chance(0.5) ? .choice : .plain
            builder.connect(from, to: to, kind: kind, label: "发展 \(attempts)")
        }

        return builder.finalized()
    }

    public static func facts(of project: StoryProject) -> Facts {
        let index = project.makeIndex()
        let orders = Dictionary(
            uniqueKeysWithValues: project.chapters.flatMap { chapter in
                chapter.order.enumerated().map { ($0.element, $0.offset) }
            }
        )

        var crossChapterEdges = 0
        var cycleEdges = 0
        for edge in project.edges {
            let fromChapter = index.nodeByID[edge.from]?.chapterID
            let toChapter = index.nodeByID[edge.to]?.chapterID
            if fromChapter != toChapter {
                crossChapterEdges += 1
            } else if let fromOrder = orders[edge.from], let toOrder = orders[edge.to], toOrder <= fromOrder {
                cycleEdges += 1
            }
        }

        let orphans = project.nodes.count { node in
            index.outgoingEdges(of: node.id).isEmpty
                && index.incomingEdges(of: node.id).isEmpty
                && !node.isEntry
        }

        let outlines = OutlineBuilder.build(project: project, index: index)
        let rows = outlines.flatMap(\.rows)

        return Facts(
            nodeCount: project.nodes.count,
            edgeCount: project.edges.count,
            chapterCount: project.chapters.count,
            branchNodes: project.nodes.count { index.outgoingEdges(of: $0.id).count > 1 },
            mergeNodes: project.nodes.count { index.incomingEdges(of: $0.id).count > 1 },
            crossChapterEdges: crossChapterEdges,
            cycleEdges: cycleEdges,
            orphanNodes: orphans,
            outlineRowCount: rows.count,
            revisitRows: rows.count { $0.role == .revisit },
            crossChapterRows: rows.count { $0.role == .crossChapter },
            detachedRows: rows.count { $0.role == .scene && $0.origin == .detached }
        )
    }

    private static func chineseNumeral(_ value: Int) -> String {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        if value <= 10 { return digits[value] }
        if value < 20 { return "十" + digits[value - 10] }
        let tens = value / 10
        let ones = value % 10
        return digits[tens] + "十" + (ones == 0 ? "" : digits[ones])
    }
}
