import Foundation

/// 叙事体检：查「故事立不立得住」，与保存前的引用校验分开。
///
/// 判定全部按**出边**算。真实工程里没有 `kind == .choice` 的节点，
/// 分支是某个场景挂了两条 `choice` 连线，所以规则不能看节点类型。
public struct AuditFinding: Identifiable, Sendable, Equatable {
    public enum Severity: String, Sendable, Comparable, CaseIterable {
        case error
        case warning
        case info

        private var rank: Int {
            switch self {
            case .error: 0
            case .warning: 1
            case .info: 2
            }
        }

        public var displayName: String {
            switch self {
            case .error: "错误"
            case .warning: "警告"
            case .info: "提示"
            }
        }

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
    }

    public var rule: String
    public var severity: Severity
    public var title: String
    public var message: String
    public var nodeID: NodeID?

    public var id: String { "\(rule):\(subjectID)" }

    /// 节点问题用节点 ID；项目级问题用 `-`。忽略记录按这个键匹配。
    public var subjectID: String { nodeID?.rawValue.uuidString ?? "-" }

    public init(
        rule: String,
        severity: Severity,
        title: String,
        message: String,
        nodeID: NodeID? = nil
    ) {
        self.rule = rule
        self.severity = severity
        self.title = title
        self.message = message
        self.nodeID = nodeID
    }
}

/// 一条规则的说明，界面与文档共用。
public struct AuditRule: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var severity: AuditFinding.Severity
    public var text: String
}

public enum NarrativeAudit {
    public static let rules: [AuditRule] = [
        .init(id: "N01", title: "断头", severity: .error, text: "正式场景有人走到它，却没有一条去向，也没标成结局。"),
        .init(id: "N02", title: "结局悬空", severity: .error, text: "标成结局，但没有任何一条线走到它。"),
        .init(id: "N03", title: "结局还有去向", severity: .error, text: "标成结局却还挂着出边，读者走完结局又回到故事里。"),
        .init(id: "N04", title: "不可达", severity: .error, text: "从任何入口都走不到这张卡。"),
        .init(id: "N05", title: "没有显式入口", severity: .error, text: "没有任何卡标成故事入口，只能靠「第一章第一张」兜底。"),
        .init(id: "N06", title: "单去向的选择点", severity: .warning, text: "挂了选项连线，却只有一个去向，选无可选。"),
        .init(id: "N07", title: "伪选择", severity: .warning, text: "两个选项指向同一张卡，也没有条件差别。"),
        .init(id: "N08", title: "无条件分叉", severity: .info, text: "分叉的两条线都没有写条件，玩家无法预期取舍。"),
        .init(id: "N09", title: "环无出口", severity: .warning, text: "一圈场景互相可达，却没有一条线通往圈外。"),
        .init(id: "N10", title: "结局太近", severity: .info, text: "到结局的步数不到全书最长路径的一半。"),
        .init(id: "N11", title: "分支不落结局", severity: .warning, text: "从这条去向出发，怎么走都到不了任何结局。"),
        .init(id: "N12", title: "没有结局", severity: .error, text: "整部作品没有标出任何结局。"),
        .init(id: "N13", title: "空场景", severity: .info, text: "正式场景既没有摘要也没有正文。"),
        .init(id: "N14", title: "同名场景", severity: .info, text: "两张正式场景用了同一个标题，导出后不好分辨。"),
        .init(id: "N15", title: "主线未标注", severity: .info, text: "有分叉但没有标主线去向，推导会按第一条出边兜底。"),
        .init(id: "N16", title: "伏笔未收", severity: .warning, text: "线索有埋点没有收点（线索落地后启用）。"),
        .init(id: "N17", title: "收在埋之前", severity: .error, text: "同一线索的收点早于埋点（线索落地后启用）。"),
        .init(id: "N18", title: "设定冲突", severity: .warning, text: "两条已确认设定同名，正文却不一致。"),
        .init(id: "N19", title: "人物断层", severity: .info, text: "人物在章序列中间连续两章不出场，前后都有出场。"),
        .init(id: "N20", title: "类型与结构脱节", severity: .info, text: "选择点没有分叉，或事件卡靠选项连线分叉。"),
        .init(id: "N21", title: "线性结构", severity: .info, text: "全书没有任何分叉，所有场景排成一条线。"),
    ]

    /// 体检。默认按 `project.auditWaivers` 过滤掉已忽略项。
    public static func run(project: StoryProject, includeWaived: Bool = false) -> [AuditFinding] {
        var findings = compute(project)
        if !includeWaived {
            let waived = Set(project.auditWaivers.map(\.waiverKey))
            findings = findings.filter { !waived.contains($0.id) }
        }
        return findings.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
            if lhs.rule != rhs.rule { return lhs.rule < rhs.rule }
            return lhs.id < rhs.id
        }
    }

    /// 当前被忽略掉的问题（用于「已忽略 N 条」）。
    public static func waivedFindings(in project: StoryProject) -> [AuditFinding] {
        let waived = Set(project.auditWaivers.map(\.waiverKey))
        return compute(project).filter { waived.contains($0.id) }
    }

    // MARK: 计算

    private static func compute(_ project: StoryProject) -> [AuditFinding] {
        let index = project.makeIndex()
        let drafts = project.nodes.filter { $0.status == .draft }
        let draftIDs = Set(drafts.map(\.id))
        let entries = project.nodes.filter(\.isEntry).map(\.id)
        let reachable = reachableNodes(from: entries, index: index, project: project)
        let starts = entryStarts(entries: entries, index: index, project: project)
        let depths = bfsDepths(from: starts, index: index)
        let endings = drafts.filter { $0.kind == .ending }
        let endingReach = reverseReachable(from: endings.map(\.id), index: index)
        var findings: [AuditFinding] = []

        for node in drafts {
            let outgoing = index.outgoingEdges(of: node.id)
            let incoming = index.incomingEdges(of: node.id)
            let isEnding = node.kind == .ending

            if !isEnding, !incoming.isEmpty, outgoing.isEmpty {
                findings.append(.init(
                    rule: "N01", severity: .error, title: CoreText.localize("断头"),
                    message: String(format: CoreText.localize("「%@」有人走到它，却没有去向。补一条线，或标成结局。"), node.title),
                    nodeID: node.id
                ))
            }
            if isEnding, incoming.isEmpty {
                findings.append(.init(
                    rule: "N02", severity: .error, title: CoreText.localize("结局悬空"),
                    message: String(format: CoreText.localize("「%@」标成了结局，但没有任何一条线走到它。"), node.title),
                    nodeID: node.id
                ))
            }
            if isEnding, !outgoing.isEmpty {
                findings.append(.init(
                    rule: "N03", severity: .error, title: CoreText.localize("结局还有去向"),
                    message: String(format: CoreText.localize("「%@」是结局，却还挂着 %lld 条出边。"), node.title, outgoing.count),
                    nodeID: node.id
                ))
            }
            if !node.isEntry, !reachable.contains(node.id) {
                findings.append(.init(
                    rule: "N04", severity: .error, title: CoreText.localize("不可达"),
                    message: String(format: CoreText.localize("「%@」从入口走不到，读者永远见不到它。"), node.title),
                    nodeID: node.id
                ))
            }
            if node.summary.isEmpty, node.body.isEmpty {
                findings.append(.init(
                    rule: "N13", severity: .info, title: CoreText.localize("空场景"),
                    message: String(format: CoreText.localize("「%@」既没有摘要也没有正文。"), node.title),
                    nodeID: node.id
                ))
            }
            findings.append(contentsOf: choiceFindings(node: node, outgoing: outgoing))
            findings.append(contentsOf: typeFindings(node: node, outgoing: outgoing))

            // N11：非结局卡上，走不进任何结局的出边。
            if !isEnding, !outgoing.isEmpty, !endings.isEmpty {
                let deadEnds = outgoing.filter { !endingReach.contains($0.to) }
                if !deadEnds.isEmpty {
                    findings.append(.init(
                        rule: "N11", severity: .warning, title: CoreText.localize("分支不落结局"),
                        message: String(format: CoreText.localize("「%@」有 %lld 条去向怎么走都到不了结局。"), node.title, deadEnds.count),
                        nodeID: node.id
                    ))
                }
            }
        }

        // N10：结局太近。只看最短步数；全书最大层数按入口 BFS。
        if let maxDepth = depths.values.max(), !endings.isEmpty {
            for ending in endings {
                guard let steps = depths[ending.id] else { continue }
                if Double(steps) < Double(maxDepth) / 2.0 {
                    findings.append(.init(
                        rule: "N10", severity: .info, title: CoreText.localize("结局太近"),
                        message: String(format: CoreText.localize("「%@」离入口只有 %lld 步，全书最长路径 %lld 层。"), ending.title, steps, maxDepth),
                        nodeID: ending.id
                    ))
                }
            }
        }

        findings.append(contentsOf: cycleFindings(drafts: drafts, draftIDs: draftIDs, index: index))
        findings.append(contentsOf: duplicateTitles(drafts))
        findings.append(contentsOf: settingConflicts(project))
        findings.append(contentsOf: characterGaps(project))
        findings.append(contentsOf: threadFindings(project))
        findings.append(contentsOf: projectLevel(project, drafts: drafts, entries: entries))

        // 抑制：没有入口时不报 N04；没有结局时不报 N10 / N11。
        if entries.isEmpty {
            findings.removeAll { $0.rule == "N04" }
        }
        if endings.isEmpty {
            findings.removeAll { $0.rule == "N10" || $0.rule == "N11" }
        }
        return findings
    }

    /// 从入口能走到的卡。
    public static func reachableNodes(
        from entries: [NodeID],
        index: ProjectIndex,
        project: StoryProject
    ) -> Set<NodeID> {
        var seen: Set<NodeID> = []
        var stack = entryStarts(entries: entries, index: index, project: project)
        while let id = stack.popLast() {
            guard seen.insert(id).inserted else { continue }
            stack.append(contentsOf: index.outgoingEdges(of: id).map(\.to))
        }
        return seen
    }

    private static func entryStarts(
        entries: [NodeID],
        index: ProjectIndex,
        project: StoryProject
    ) -> [NodeID] {
        if !entries.isEmpty { return entries }
        guard let firstChapter = project.chapters.first else { return [] }
        return index.nodes(in: firstChapter.id).prefix(1).map(\.id)
    }

    private static func bfsDepths(from starts: [NodeID], index: ProjectIndex) -> [NodeID: Int] {
        var depth: [NodeID: Int] = [:]
        var queue: [NodeID] = []
        for id in starts where depth[id] == nil {
            depth[id] = 0
            queue.append(id)
        }
        var head = 0
        while head < queue.count {
            let id = queue[head]
            head += 1
            let current = depth[id] ?? 0
            for edge in index.outgoingEdges(of: id) where depth[edge.to] == nil {
                depth[edge.to] = current + 1
                queue.append(edge.to)
            }
        }
        return depth
    }

    /// 反向可达：哪些卡能走到任一结局。
    private static func reverseReachable(from endings: [NodeID], index: ProjectIndex) -> Set<NodeID> {
        var seen: Set<NodeID> = []
        var stack = endings
        while let id = stack.popLast() {
            guard seen.insert(id).inserted else { continue }
            stack.append(contentsOf: index.incomingEdges(of: id).map(\.from))
        }
        return seen
    }

    // MARK: 分叉

    private static func choiceFindings(node: StoryNode, outgoing: [StoryEdge]) -> [AuditFinding] {
        guard node.kind != .ending else { return [] }
        let choiceEdges = outgoing.filter { $0.kind == .choice }
        var findings: [AuditFinding] = []

        if !choiceEdges.isEmpty, outgoing.count == 1 {
            findings.append(.init(
                rule: "N06", severity: .warning, title: CoreText.localize("单去向的选择点"),
                message: String(format: CoreText.localize("「%@」只有一条去向，选项连不成选择。"), node.title),
                nodeID: node.id
            ))
        }
        if outgoing.count >= 2 {
            let targets = Set(outgoing.map(\.to))
            if targets.count == 1, outgoing.allSatisfy({ $0.condition.isEmpty }) {
                findings.append(.init(
                    rule: "N07", severity: .warning, title: CoreText.localize("伪选择"),
                    message: String(format: CoreText.localize("「%@」的几个选项都通向同一张卡，也没有条件差别。"), node.title),
                    nodeID: node.id
                ))
            }
            if outgoing.allSatisfy({ $0.condition.isEmpty }) {
                findings.append(.init(
                    rule: "N08", severity: .info, title: CoreText.localize("无条件分叉"),
                    message: String(format: CoreText.localize("「%@」有 %lld 条分支，都没有写条件。"), node.title, outgoing.count),
                    nodeID: node.id
                ))
            }
            if !outgoing.contains(where: \.isMainline) {
                findings.append(.init(
                    rule: "N15", severity: .info, title: CoreText.localize("主线未标注"),
                    message: String(format: CoreText.localize("「%@」有分叉但没标主线去向，推导会按第一条出边兜底。"), node.title),
                    nodeID: node.id
                ))
            }
        }
        return findings
    }

    private static func typeFindings(node: StoryNode, outgoing: [StoryEdge]) -> [AuditFinding] {
        var findings: [AuditFinding] = []
        if node.kind == .choice, outgoing.count < 2 {
            findings.append(.init(
                rule: "N20", severity: .info, title: CoreText.localize("类型与结构脱节"),
                message: String(format: CoreText.localize("「%@」标成选择点，却只有 %lld 条去向。"), node.title, outgoing.count),
                nodeID: node.id
            ))
        }
        if node.kind == .event, outgoing.count >= 2, outgoing.contains(where: { $0.kind == .choice }) {
            findings.append(.init(
                rule: "N20", severity: .info, title: "类型与结构脱节",
                message: String(format: CoreText.localize("「%@」是事件卡，却挂着选项连线。考虑改成选择点，或把连线改回因果。"), node.title),
                nodeID: node.id
            ))
        }
        return findings
    }

    // MARK: N09 环无出口

    private static func cycleFindings(
        drafts: [StoryNode],
        draftIDs: Set<NodeID>,
        index: ProjectIndex
    ) -> [AuditFinding] {
        var adjacency: [NodeID: [NodeID]] = [:]
        var reverse: [NodeID: [NodeID]] = [:]
        for node in drafts {
            adjacency[node.id] = []
            reverse[node.id] = []
        }
        for node in drafts {
            for edge in index.outgoingEdges(of: node.id) where draftIDs.contains(edge.to) {
                adjacency[node.id, default: []].append(edge.to)
                reverse[edge.to, default: []].append(node.id)
            }
        }

        var findings: [AuditFinding] = []
        for component in stronglyConnectedComponents(nodes: drafts.map(\.id), adjacency: adjacency, reverse: reverse) {
            let members = Set(component)
            let isCycle = component.count > 1
                || component.contains { adjacency[$0]?.contains($0) == true }
            guard isCycle else { continue }
            let hasOutlet = component.contains { id in
                (adjacency[id] ?? []).contains { !members.contains($0) }
            }
            guard !hasOutlet else { continue }
            let representative = component.min { $0.rawValue.uuidString < $1.rawValue.uuidString }
            let title = representative.flatMap { index.nodeByID[$0]?.title } ?? "一圈场景"
            findings.append(.init(
                rule: "N09", severity: .warning, title: CoreText.localize("环无出口"),
                message: String(format: CoreText.localize("「%@」所在的一圈互相可达，却没有一条线通往圈外。"), title),
                nodeID: representative
            ))
        }
        return findings
    }

    /// Kosaraju，两遍迭代 DFS；500 节点也不会把递归栈打穿。
    private static func stronglyConnectedComponents(
        nodes: [NodeID],
        adjacency: [NodeID: [NodeID]],
        reverse: [NodeID: [NodeID]]
    ) -> [[NodeID]] {
        var visited: Set<NodeID> = []
        var order: [NodeID] = []
        for start in nodes where !visited.contains(start) {
            var stack: [(NodeID, Int)] = [(start, 0)]
            visited.insert(start)
            while let (current, next) = stack.popLast() {
                let edges = adjacency[current] ?? []
                if next < edges.count {
                    stack.append((current, next + 1))
                    let target = edges[next]
                    if visited.insert(target).inserted {
                        stack.append((target, 0))
                    }
                } else {
                    order.append(current)
                }
            }
        }

        var assigned: Set<NodeID> = []
        var components: [[NodeID]] = []
        for start in order.reversed() where !assigned.contains(start) {
            var component: [NodeID] = []
            var stack = [start]
            assigned.insert(start)
            while let current = stack.popLast() {
                component.append(current)
                for target in reverse[current] ?? [] where assigned.insert(target).inserted {
                    stack.append(target)
                }
            }
            components.append(component)
        }
        return components
    }

    // MARK: 项目级

    private static func duplicateTitles(_ drafts: [StoryNode]) -> [AuditFinding] {
        var buckets: [String: [StoryNode]] = [:]
        for node in drafts where !node.title.isEmpty {
            buckets[node.title, default: []].append(node)
        }
        return buckets
            .filter { $0.value.count > 1 }
            .sorted { $0.key < $1.key }
            .map { title, nodes in
                AuditFinding(
                    rule: "N14", severity: .info, title: CoreText.localize("同名场景"),
                    message: String(format: CoreText.localize("「%@」有 %lld 张同名卡。"), title, nodes.count),
                    nodeID: nodes.first?.id
                )
            }
    }

    private static func settingConflicts(_ project: StoryProject) -> [AuditFinding] {
        let confirmed = project.settings.filter(\.isConfirmed)
        var buckets: [String: [Setting]] = [:]
        for setting in confirmed where !setting.title.isEmpty {
            buckets[setting.title, default: []].append(setting)
        }
        return buckets
            .filter { $0.value.count > 1 }
            .filter { Set($0.value.map(\.text)).count > 1 }
            .sorted { $0.key < $1.key }
            .map { title, settings in
                AuditFinding(
                    rule: "N18", severity: .warning, title: CoreText.localize("设定冲突"),
                    message: String(format: CoreText.localize("「%@」有 %lld 条已确认设定，正文不一致。"), title, settings.count),
                    nodeID: settings.first?.attachedNodeIDs.first
                )
            }
    }

    private static func characterGaps(_ project: StoryProject) -> [AuditFinding] {
        let chapters = project.chapters
        guard chapters.count >= 3 else { return [] }
        let drafts = project.nodes.filter { $0.status == .draft }
        var findings: [AuditFinding] = []

        for character in project.characters {
            let appeared = chapters.enumerated().compactMap { index, chapter -> Int? in
                drafts.contains {
                    $0.chapterID == chapter.id && $0.characterIDs.contains(character.id)
                } ? index : nil
            }
            guard appeared.count >= 2 else { continue }
            for (before, after) in zip(appeared, appeared.dropFirst()) where after - before >= 3 {
                let chapterID = chapters[after].id
                let landing = drafts.first {
                    $0.chapterID == chapterID && $0.characterIDs.contains(character.id)
                }
                findings.append(.init(
                    rule: "N19", severity: .info, title: CoreText.localize("人物断层"),
                    message: String(format: CoreText.localize("「%@」在第 %lld 与第 %lld 章之间连续 %lld 章没出场。"), character.name, before + 1, after + 1, after - before - 1),
                    nodeID: landing?.id
                ))
                break
            }
        }
        return findings
    }

    private static func threadFindings(_ project: StoryProject) -> [AuditFinding] {
        var rank: [NodeID: Int] = [:]
        var counter = 0
        for chapter in project.chapters {
            for nodeID in chapter.order where rank[nodeID] == nil {
                rank[nodeID] = counter
                counter += 1
            }
        }
        for node in project.nodes where rank[node.id] == nil {
            rank[node.id] = counter
            counter += 1
        }

        var findings: [AuditFinding] = []
        for thread in project.threads {
            let plants = thread.entries.filter { $0.role == .plant }
            let payoffs = thread.entries.filter { $0.role == .payoff || $0.role == .subvert }
            if !plants.isEmpty, payoffs.isEmpty {
                findings.append(.init(
                    rule: "N16", severity: .warning, title: CoreText.localize("伏笔未收"),
                    message: String(format: CoreText.localize("「%@」有 %lld 个埋点，还没有收点。"), thread.name, plants.count),
                    nodeID: plants.first?.nodeID
                ))
            }
            let firstPlant = plants.min { (rank[$0.nodeID] ?? .max) < (rank[$1.nodeID] ?? .max) }
            let firstPayoff = payoffs.min { (rank[$0.nodeID] ?? .max) < (rank[$1.nodeID] ?? .max) }
            if let firstPlant, let firstPayoff,
               (rank[firstPayoff.nodeID] ?? .max) < (rank[firstPlant.nodeID] ?? .max) {
                findings.append(.init(
                    rule: "N17", severity: .error, title: CoreText.localize("收在埋之前"),
                    message: String(format: CoreText.localize("「%@」的收点排在埋点之前。"), thread.name),
                    nodeID: firstPayoff.nodeID
                ))
            }
        }
        return findings
    }

    private static func projectLevel(
        _ project: StoryProject,
        drafts: [StoryNode],
        entries: [NodeID]
    ) -> [AuditFinding] {
        var findings: [AuditFinding] = []
        if entries.isEmpty {
            findings.append(.init(
                rule: "N05", severity: .error, title: CoreText.localize("没有显式入口"),
                message: CoreText.localize("没有任何卡标成故事入口，只能靠「第一章第一张」兜底。"),
                nodeID: project.chapters.first.flatMap { chapter in
                    chapter.order.first
                }
            ))
        }
        if !drafts.contains(where: { $0.kind == .ending }) {
            findings.append(.init(
                rule: "N12", severity: .error, title: CoreText.localize("没有结局"),
                message: CoreText.localize("整部作品还没有标出任何结局。"),
                nodeID: nil
            ))
        }
        let index = project.makeIndex()
        if !drafts.contains(where: { index.outgoingEdges(of: $0.id).count >= 2 }) {
            findings.append(.init(
                rule: "N21", severity: .info, title: CoreText.localize("线性结构"),
                message: CoreText.localize("全书没有任何分叉，所有场景排成一条线。"),
                nodeID: nil
            ))
        }
        return findings
    }
}
