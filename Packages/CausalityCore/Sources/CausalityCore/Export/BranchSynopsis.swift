import Foundation

/// 一条分支的梗概。
///
/// 只用卡片的标题与摘要首句，不搬正文；每块最多四句，目的是能一眼读完。
/// 路径用节点集合去重，避免同一个故事换一种走法被算成两条分支。
public struct BranchBlock: Sendable, Equatable, Identifiable {
    public var id: String
    /// 「守密线」这种短名，取自分叉处那条连线的文案。
    public var label: String
    public var sentences: [String]
    public var nodeIDs: [NodeID]
    /// 被句数上限截掉了几场。
    public var omitted: Int

    public init(label: String, sentences: [String], nodeIDs: [NodeID], omitted: Int = 0) {
        self.id = "\(label)-\(nodeIDs.first?.rawValue.uuidString ?? "-")"
        self.label = label
        self.sentences = sentences
        self.nodeIDs = nodeIDs
        self.omitted = omitted
    }

    public var text: String {
        text(localize: { CoreText.localize($0) })
    }

    /// 导出到别的语言时传对应语言的 localize，别改全局 CoreText。
    public func text(localize: (String) -> String) -> String {
        guard omitted > 0, sentences.count > 1 else { return sentences.joined() }
        let head = sentences.dropLast().joined()
        let tail = sentences.last ?? ""
        return head + String(format: localize("……（下面还有 %lld 场）"), omitted) + tail
    }

    public var cardCount: Int { nodeIDs.count }
}

public struct BranchSynopsis: Sendable, Equatable {
    public enum Mode: String, Sendable {
        /// 公共前缀 → 各分支 → 共尾，汇合只讲一次。
        case segments
        /// 每条路径一整段，方便整段复制。
        case perPath = "per-path"
    }

    public struct EndingInfo: Sendable, Equatable, Identifiable {
        public var id: NodeID
        public var title: String
        public var cardCount: Int
    }

    /// 结局这一组的角标与「更多」。
    public struct EndingStats: Sendable, Equatable {
        public var wordCount: Int
        public var choiceCount: Int
        /// 只在这条结局路上出现的正式场景数。
        public var exclusiveCount: Int
        public var shortestSteps: Int?
        public var longestSteps: Int?
        /// 有别的结局时，独占卡 ≤ 2 视为结局太薄。
        public var thin: Bool
    }

    public var endingID: NodeID
    public var endingTitle: String
    /// 这条结局路上的卡数与去重后的卡。
    public var cardCount: Int
    public var blocks: [BranchBlock]
    /// 分支太多，只按分叉分块渲染。
    public var truncated: Bool
    /// 卡数、字数、选择点、独占卡与步数。
    public var stats: EndingStats

    public var text: String {
        blocks.map { "\($0.label)｜\($0.text)" }.joined(separator: "\n")
    }

    // MARK: - 入口

    /// 工程里所有结局，按章序与卡序排。
    public static func endings(in project: StoryProject) -> [EndingInfo] {
        project.nodes
            .filter { $0.kind == .ending && $0.status == .draft }
            .map { node in
                let route = StoryRoute.paths(to: node.id, in: project)
                return EndingInfo(id: node.id, title: node.title, cardCount: route.nodeIDs.count)
            }
            .sorted { $0.title < $1.title }
    }

    /// 生成某个结局的分支梗概。结局不存在时给空结果。
    public static func make(
        project: StoryProject,
        endingID: NodeID,
        mode: Mode = .segments,
        localize: (String) -> String = { CoreText.localize($0) }
    ) -> BranchSynopsis {
        let index = project.makeIndex()
        let title = index.nodeByID[endingID]?.title ?? localize("结局")
        let paths = Paths.enumerate(to: endingID, in: project, index: index)
        let route = StoryRoute.paths(to: endingID, in: project)

        let stats = stats(
            project: project,
            endingID: endingID,
            route: route,
            paths: paths.paths,
            truncated: paths.truncated,
            index: index
        )

        guard !paths.paths.isEmpty else {
            return BranchSynopsis(
                endingID: endingID,
                endingTitle: title,
                cardCount: route.nodeIDs.count,
                blocks: [],
                truncated: paths.truncated,
                stats: stats
            )
        }

        let blocks: [BranchBlock]
        switch mode {
        case .perPath:
            blocks = paths.paths.enumerated().map { offset, path in
                render(
                    path: path,
                    index: index,
                    project: project,
                    label: label(for: offset, path: path, index: index, localize: localize),
                    localize: localize
                )
            }
        case .segments:
            blocks = renderSegments(paths: paths.paths, index: index, project: project, localize: localize)
        }

        return BranchSynopsis(
            endingID: endingID,
            endingTitle: title,
            cardCount: route.nodeIDs.count,
            blocks: blocks,
            truncated: paths.truncated,
            stats: stats
        )
    }

    /// 每个结局组角标上的数字。独占卡按「不在其它结局路上」算；只有一个结局时不判太薄。
    private static func stats(
        project: StoryProject,
        endingID: NodeID,
        route: StoryRoute,
        paths: [Path],
        truncated: Bool,
        index: ProjectIndex
    ) -> EndingStats {
        let otherEndings = endings(in: project).filter { $0.id != endingID }
        var otherNodes: Set<NodeID> = []
        for other in otherEndings {
            otherNodes.formUnion(StoryRoute.paths(to: other.id, in: project).nodeIDs)
        }
        let draftsOnRoute = route.nodeIDs.filter { index.nodeByID[$0]?.status == .draft }
        let exclusive = draftsOnRoute.filter { !otherNodes.contains($0) }
        let steps = paths.map { $0.nodeIDs.count - 1 }
        return EndingStats(
            wordCount: WordCount.count(of: route, in: project),
            choiceCount: draftsOnRoute.count { index.outgoingEdges(of: $0).count >= 2 },
            exclusiveCount: exclusive.count,
            shortestSteps: steps.min(),
            longestSteps: steps.isEmpty ? nil : steps.max(),
            thin: !otherEndings.isEmpty && exclusive.count <= 2
        )
    }

    /// 被所有结局共同经过的章。「必读墙」告警用。
    public static func sharedChapters(in project: StoryProject) -> [Chapter] {
        let all = endings(in: project)
        guard all.count >= 2 else { return [] }
        var common: Set<ChapterID>?
        for ending in all {
            let route = StoryRoute.paths(to: ending.id, in: project)
            let chapters = Set(route.nodeIDs.compactMap { project.node($0)?.chapterID })
            common = common.map { $0.intersection(chapters) } ?? chapters
        }
        return project.chapters.filter { common?.contains($0.id) ?? false }
    }

    // MARK: - 渲染

    private struct Path {
        var nodeIDs: [NodeID]
        /// 与 nodeIDs 一一对应：进入该节点所用的连线，首张为 nil。
        var incomingEdges: [StoryEdge?]
        var key: String
    }

    private enum Paths {
        struct Result {
            var paths: [Path]
            var truncated: Bool
        }

        /// 从入口枚举通往结局的路径。按节点集合去重，上限 24 条、5000 次展开。
        static func enumerate(to endingID: NodeID, in project: StoryProject, index: ProjectIndex) -> Result {
            var starts = project.nodes.filter(\.isEntry).map(\.id)
            if starts.isEmpty, let first = project.chapters.first {
                starts = index.nodes(in: first.id).prefix(1).map(\.id)
            }

            let limit = 24
            let expansionBudget = 5000
            var expansions = 0
            var found: [Path] = []
            var seenKeys: Set<String> = []
            var truncated = false

            func walk(
                _ nodeID: NodeID,
                nodes: [NodeID],
                incoming: [StoryEdge?],
                visited: Set<NodeID>,
                via edge: StoryEdge?
            ) {
                guard expansions < expansionBudget else { truncated = true; return }
                expansions += 1

                var nodes = nodes
                var incoming = incoming
                if nodes.last != nodeID {
                    nodes.append(nodeID)
                    incoming.append(edge)
                }

                if nodeID == endingID {
                    let key = nodes.map(\.rawValue.uuidString).joined(separator: ">")
                    if seenKeys.insert(key).inserted {
                        if found.count >= limit {
                            truncated = true
                        } else {
                            found.append(Path(nodeIDs: nodes, incomingEdges: incoming, key: key))
                        }
                    }
                    return
                }
                guard index.nodeByID[nodeID]?.kind != .ending else {
                    // 走到别的结局就停，不穿过去。
                    if nodeID != endingID { return }
                    return
                }

                for edge in index.outgoingEdges(of: nodeID) {
                    guard !visited.contains(edge.to) else { continue }
                    walk(
                        edge.to,
                        nodes: nodes,
                        incoming: incoming,
                        visited: visited.union([edge.to]),
                        via: edge
                    )
                    if found.count >= limit { truncated = true; return }
                }
            }

            for start in starts {
                walk(start, nodes: [], incoming: [], visited: [start], via: nil)
            }
            return Result(paths: found, truncated: truncated)
        }
    }

    private static func label(
        for offset: Int,
        path: Path,
        index: ProjectIndex,
        localize: (String) -> String
    ) -> String {
        let edges = path.incomingEdges.compactMap { $0 }
        if let choice = edges.first(where: { $0.kind == .choice && !$0.label.isEmpty }) {
            return choice.label
        }
        if let labeled = edges.first(where: { !$0.label.isEmpty }) {
            return labeled.label
        }
        return String(format: localize("路径 %lld"), offset + 1)
    }

    private static func render(
        path: Path,
        index: ProjectIndex,
        project: StoryProject,
        label: String,
        localize: (String) -> String
    ) -> BranchBlock {
        var items: [(id: NodeID, sentence: String)] = []
        for (offset, nodeID) in path.nodeIDs.enumerated() {
            guard let node = index.nodeByID[nodeID] else { continue }
            var sentence = Self.sentence(for: node)
            if offset > 0,
               let edge = path.incomingEdges[offset],
               edge.kind == .choice,
               !edge.label.isEmpty {
                sentence = String(format: localize("若%@，"), edge.label) + sentence
            }
            items.append((nodeID, sentence))
        }
        return block(label: label, items: items)
    }

    /// 分段渲染：公共前缀讲一次，各分支各一段，共尾（汇合）讲一次。
    private static func renderSegments(
        paths: [Path],
        index: ProjectIndex,
        project: StoryProject,
        localize: (String) -> String
    ) -> [BranchBlock] {
        guard let first = paths.first else { return [] }

        var prefixCount = 0
        while prefixCount < first.nodeIDs.count {
            let candidate = first.nodeIDs[prefixCount]
            guard paths.allSatisfy({ $0.nodeIDs.count > prefixCount && $0.nodeIDs[prefixCount] == candidate }) else { break }
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < first.nodeIDs.count - prefixCount {
            let candidate = first.nodeIDs[first.nodeIDs.count - 1 - suffixCount]
            let ok = paths.allSatisfy { path in
                path.nodeIDs.count - 1 - suffixCount >= prefixCount
                    && path.nodeIDs[path.nodeIDs.count - 1 - suffixCount] == candidate
            }
            guard ok else { break }
            suffixCount += 1
        }

        let prefix = Array(first.nodeIDs.prefix(prefixCount))
        let suffix = suffixCount > 0 ? Array(first.nodeIDs.suffix(suffixCount)) : []

        var middles: [String: (nodes: [NodeID], label: String)] = [:]
        var order: [String] = []
        for path in paths {
            let end = path.nodeIDs.count - suffixCount
            guard end > prefixCount else { continue }
            let middle = Array(path.nodeIDs[prefixCount..<end])
            let key = middle.map(\.rawValue.uuidString).joined(separator: ">")
            if middles[key] == nil {
                middles[key] = (
                    middle,
                    middleLabel(path: path, prefixCount: prefixCount, index: index, localize: localize)
                )
                order.append(key)
            }
        }

        var blocks: [BranchBlock] = []
        if !prefix.isEmpty {
            blocks.append(block(label: localize("开始"), items: items(for: prefix, index: index)))
        }
        for key in order {
            guard let middle = middles[key] else { continue }
            blocks.append(block(label: middle.label, items: items(for: middle.nodes, index: index)))
        }
        if !suffix.isEmpty {
            let label = index.nodeByID[suffix.first!]?.kind == .ending
                ? localize("结局")
                : localize("汇合")
            blocks.append(block(label: label, items: items(for: suffix, index: index)))
        }
        return blocks
    }

    /// 分支的短名：分叉后第一条连线的文案。
    private static func middleLabel(
        path: Path,
        prefixCount: Int,
        index: ProjectIndex,
        localize: (String) -> String
    ) -> String {
        guard prefixCount < path.incomingEdges.count, let edge = path.incomingEdges[prefixCount] else {
            return localize("分支")
        }
        if !edge.label.isEmpty { return edge.label }
        let target = index.nodeByID[edge.to]?.title ?? "分支"
        return String(format: localize("通向「%@」"), target)
    }

    private static func items(for nodes: [NodeID], index: ProjectIndex) -> [(id: NodeID, sentence: String)] {
        nodes.compactMap { id in
            guard let node = index.nodeByID[id] else { return nil }
            return (id, sentence(for: node))
        }
    }

    /// 每块最多四句：句子多时留前三句与最后一句（最后一句通常是结局），中间记成省略。
    private static func block(label: String, items: [(id: NodeID, sentence: String)]) -> BranchBlock {
        guard items.count > 4 else {
            return BranchBlock(label: label, sentences: items.map(\.sentence), nodeIDs: items.map(\.id))
        }
        let head = Array(items.prefix(3)).map(\.sentence)
        let tail: [String] = items.last.map { [$0.sentence] } ?? []
        return BranchBlock(
            label: label,
            sentences: head + tail,
            nodeIDs: items.map(\.id),
            omitted: items.count - 4
        )
    }

    /// 一句：优先用摘要首句，没有摘要就退到标题。
    static func sentence(for node: StoryNode) -> String {
        let summary = node.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = summary.split(separator: "。").first, !first.isEmpty {
            return String(first) + "。"
        }
        return node.title + "。"
    }
}
