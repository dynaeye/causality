import Foundation

/// 字段级对照，供逐项审阅。
public struct FieldDiff: Identifiable, Sendable, Equatable, Hashable {
    public var field: String
    public var before: String
    public var after: String

    public var id: String { field }

    public init(field: String, before: String, after: String) {
        self.field = field
        self.before = before
        self.after = after
    }
}

/// 提案里的一项。采纳、拒绝、只作建议都由这一层决定。
public struct ProposalItem: Identifiable, Sendable, Equatable {
    public enum Action: String, Sendable, Equatable {
        case addNode
        case addEdge
        case changeNode
        case changeEdge
        case changeSetting
        case removeNode
        case removeEdge
        case removeSetting

        public var displayName: String {
            switch self {
            case .addNode: CoreText.text("新增场景")
            case .addEdge: CoreText.text("新增发展线")
            case .changeNode: CoreText.text("修改场景")
            case .changeEdge: CoreText.text("修改发展线")
            case .changeSetting: CoreText.text("修改事实设定")
            case .removeNode: CoreText.text("移除场景")
            case .removeEdge: CoreText.text("移除发展线")
            case .removeSetting: CoreText.text("移除事实设定")
            }
        }
    }

    public enum Outcome: Sendable, Equatable {
        case accept
        case reject(String)
        case suggestion(String)

        public var isAccepted: Bool {
            if case .accept = self { return true }
            return false
        }

        public var explanation: String? {
            switch self {
            case .accept: nil
            case let .reject(reason): reason
            case let .suggestion(reason): reason
            }
        }
    }

    public var id: String
    public var action: Action
    public var title: String
    public var detail: [FieldDiff]
    public var outcome: Outcome
    public var group: String
    public var operations: [EditOperation]
}

public struct ProposalGroup: Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var itemIDs: [String]
    public var adoptableItemIDs: [String]
}

public enum ProposalStatus: Sendable, Equatable {
    case ready
    case stale(base: Int, current: Int)
    case conflicted([String])
}

public struct ValidatedProposal: Sendable, Equatable {
    public var proposal: AIProposal
    public var status: ProposalStatus
    public var items: [ProposalItem]
    public var groups: [ProposalGroup]
    public var notes: [String]

    public var acceptedItems: [ProposalItem] { items.filter { $0.outcome.isAccepted } }
    public var rejectedItems: [ProposalItem] {
        items.filter { if case .reject = $0.outcome { return true } else { return false } }
    }
    public var suggestionItems: [ProposalItem] {
        items.filter { if case .suggestion = $0.outcome { return true } else { return false } }
    }
    public var acceptedOperations: [EditOperation] { acceptedItems.flatMap(\.operations) }

    /// 只取其中几项的操作，用来按组采纳。
    public func operations(for itemIDs: [String]) -> [EditOperation] {
        let wanted = Set(itemIDs)
        return items
            .filter { wanted.contains($0.id) && $0.outcome.isAccepted }
            .flatMap(\.operations)
    }
    public var isAdoptable: Bool { status == .ready && !acceptedOperations.isEmpty }
}

public enum ProposalApplyError: Error, Equatable, CustomStringConvertible {
    case stale(base: Int, current: Int)
    case conflicted([String])
    case duplicate(UUID)
    case empty
    case failed(String)

    public var description: String {
        switch self {
        case let .stale(base, current):
            CoreText.format("提案基于版本 %lld，项目已到 %lld，请重新生成", base, current)
        case let .conflicted(titles):
            CoreText.format("这些场景在等待期间被改过：%@", titles.joined(separator: "、"))
        case .duplicate: CoreText.text("这份提案已经采纳过")
        case .empty: CoreText.text("没有可采纳的改动")
        case let .failed(reason): reason
        }
    }
}

/// 校验器把一份提案翻译成“逐项结果 + 可采纳的编辑操作”。
///
/// 检查顺序：项目版本 → 引用 → 范围 → 锁定 → 作者改动冲突 → 结构合法性。
/// 任一环节不过的项被标成拒绝或建议，其余项照常可用于成组采纳。
public enum ProposalValidator {
    public static func validate(
        _ proposal: AIProposal,
        in project: StoryProject,
        scope: ProposalScope
    ) -> ValidatedProposal {
        var builder = ProposalBuilder(proposal: proposal, project: project, scope: scope)
        return builder.run()
    }
}

struct ProposalBuilder {
    let proposal: AIProposal
    let project: StoryProject
    let scope: ProposalScope

    var working: StoryProject
    var items: [ProposalItem] = []
    var notes: [String] = []
    var conflicts: [String] = []
    var refMap: [String: NodeID] = [:]
    /// 同一份提案里对同一节点的多次修改，第二次不再做版本比对。
    var touchedNodeIDs: Set<NodeID> = []
    var counter = 0

    init(proposal: AIProposal, project: StoryProject, scope: ProposalScope) {
        self.proposal = proposal
        self.project = project
        self.scope = scope
        self.working = project
    }

    mutating func run() -> ValidatedProposal {
        notes = proposal.payload.notes

        for draft in proposal.payload.nodes {
            applyNodeDraft(draft)
        }
        for draft in proposal.payload.edges {
            applyEdgeDraft(draft)
        }
        for change in proposal.payload.changes {
            applyChange(change)
        }
        for removal in proposal.payload.removals {
            applyRemoval(removal)
        }

        let status: ProposalStatus
        if !conflicts.isEmpty {
            status = .conflicted(conflicts)
        } else if proposal.baseRevision != project.revision {
            status = .stale(base: proposal.baseRevision, current: project.revision)
        } else {
            status = .ready
        }

        let grouped = groupItems()
        return ValidatedProposal(
            proposal: proposal,
            status: status,
            items: items,
            groups: grouped,
            notes: notes
        )
    }

    // MARK: 落地与记录

    /// 立刻落地并返回这组操作。后续步骤能看到它的效果。
    mutating func apply(_ operations: [EditOperation]) -> [EditOperation] {
        try? ProjectEditing.apply(operations, to: &working)
        return operations
    }

    /// 记录一组已经落地的操作。
    mutating func commitApplied(
        _ action: ProposalItem.Action,
        title: String,
        detail: [FieldDiff],
        operations: [EditOperation],
        group: String
    ) {
        counter += 1
        items.append(
            ProposalItem(
                id: "\(action.rawValue)-\(counter)",
                action: action,
                title: title,
                detail: detail,
                outcome: .accept,
                group: group,
                operations: operations
            )
        )
    }

    mutating func commit(
        _ action: ProposalItem.Action,
        title: String,
        detail: [FieldDiff],
        operations: [EditOperation],
        group: String
    ) {
        do {
            try ProjectEditing.apply(operations, to: &working)
        } catch {
            appendReject(action, title: title, reason: CoreText.format("结构校验未通过：%@", "\(error)"), group: group)
            return
        }
        counter += 1
        items.append(
            ProposalItem(
                id: "\(action.rawValue)-\(counter)",
                action: action,
                title: title,
                detail: detail,
                outcome: .accept,
                group: group,
                operations: operations
            )
        )
    }

    mutating func appendReject(
        _ action: ProposalItem.Action,
        title: String,
        reason: String,
        group: String
    ) {
        counter += 1
        items.append(
            ProposalItem(
                id: "\(action.rawValue)-\(counter)",
                action: action,
                title: title,
                detail: [],
                outcome: .reject(reason),
                group: group,
                operations: []
            )
        )
    }

    mutating func appendSuggestion(
        _ action: ProposalItem.Action,
        title: String,
        reason: String,
        group: String
    ) {
        counter += 1
        items.append(
            ProposalItem(
                id: "\(action.rawValue)-\(counter)",
                action: action,
                title: title,
                detail: [],
                outcome: .suggestion(reason),
                group: group,
                operations: []
            )
        )
    }

    // MARK: 引用解析

    func resolve(_ reference: String) -> NodeID? {
        if let uuid = UUID(uuidString: reference), let node = project.node(NodeID(rawValue: uuid)) {
            return node.id
        }
        if let mapped = refMap[reference] {
            return mapped
        }
        // 兼容模型直接写节点标题的情况。
        return project.nodes.first { $0.title == reference }?.id
    }

    mutating func resolveCharacters(_ names: [String], nodeTitle: String) -> [CharacterID] {
        var ids: [CharacterID] = []
        for name in names {
            if let match = working.characters.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
                ids.append(match.id)
            } else {
                notes.append(CoreText.format("未找到人物「%@」，场景「%@」没有挂上它。", name, nodeTitle))
            }
        }
        return ids
    }

    mutating func resolvePlaces(_ names: [String], nodeTitle: String) -> [PlaceID] {
        var ids: [PlaceID] = []
        for name in names {
            if let match = working.places.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
                ids.append(match.id)
            } else {
                notes.append(CoreText.format("未找到地点「%@」，场景「%@」没有挂上它。", name, nodeTitle))
            }
        }
        return ids
    }

    mutating func resolveSettings(_ titles: [String], nodeTitle: String) -> [SettingID] {
        var ids: [SettingID] = []
        for title in titles {
            if let match = working.settings.first(where: { $0.title.compare(title, options: .caseInsensitive) == .orderedSame }) {
                ids.append(match.id)
            } else {
                notes.append(CoreText.format("未找到事实设定「%@」，场景「%@」没有引用它。", title, nodeTitle))
            }
        }
        return ids
    }

    /// 新卡落位：模型给的位置优先，其次是故事板上点下的缝隙。
    func insertionIndex(for draft: NodeDraft, chapterID: ChapterID) -> Int? {
        if let afterRef = draft.afterRef,
           let anchor = resolve(afterRef),
           let chapter = working.chapter(chapterID),
           let anchorIndex = chapter.order.firstIndex(of: anchor) {
            return anchorIndex + 1
        }
        if let anchor = scope.defaultInsertAfter,
           let chapter = working.chapter(chapterID),
           let anchorIndex = chapter.order.firstIndex(of: anchor) {
            return anchorIndex + 1
        }
        return scope.defaultInsertIndex
    }

    // MARK: 成组

    /// 相互引用的改动合成一组：新节点与它的出边、同一实体的多处修改、被移除的节点与它的连线。
    func groupItems() -> [ProposalGroup] {
        var parent: [String: String] = [:]

        func find(_ value: String) -> String {
            var current = value
            while let next = parent[current], next != current {
                current = next
            }
            return current
        }

        func union(_ lhs: String, _ rhs: String) {
            let leftRoot = find(lhs)
            let rightRoot = find(rhs)
            if leftRoot != rightRoot {
                parent[rightRoot] = leftRoot
            }
        }

        for item in items {
            guard case .accept = item.outcome else { continue }
            if parent[item.id] == nil { parent[item.id] = item.id }
            union(item.id, "entity:\(item.group)")
            // 新节点引用解析出的真实 ID 与 ref 指向同一实体。
            if let nodeID = refMap[item.group] {
                union(item.id, "node:\(nodeID.rawValue.uuidString)")
            }
            for operation in item.operations {
                for key in entityKeys(of: operation) {
                    union(item.id, key)
                }
            }
        }

        var buckets: [String: [ProposalItem]] = [:]
        for item in items where parent[item.id] != nil {
            buckets[find(item.id), default: []].append(item)
        }

        var result = buckets.map { root, groupedItems in
            ProposalGroup(
                id: root,
                title: groupedItems.count == 1
                    ? (groupedItems[0].title.isEmpty ? groupedItems[0].action.displayName : groupedItems[0].title)
                    : CoreText.format("关联改动 %lld 项", groupedItems.count),
                itemIDs: groupedItems.map(\.id),
                adoptableItemIDs: groupedItems.filter { $0.outcome.isAccepted }.map(\.id)
            )
        }
        .sorted { $0.itemIDs.first ?? "" < $1.itemIDs.first ?? "" }

        // 锁定的事实设定、超出范围的改动只能当建议，单独分组放在最后。
        let suggestions = items.filter { item in
            if case .suggestion = item.outcome { return true }
            return false
        }
        if !suggestions.isEmpty {
            result.append(ProposalGroup(
                id: "suggestions",
                title: CoreText.format("只能作为建议 %lld 项", suggestions.count),
                itemIDs: suggestions.map(\.id),
                adoptableItemIDs: []
            ))
        }
        return result
    }

    func entityKeys(of operation: EditOperation) -> [String] {
        switch operation {
        case let .insertNode(node, _), let .deleteNode(node, _), let .replaceNode(_, node):
            ["node:\(node.id.rawValue.uuidString)"]
        case let .insertEdge(edge, _), let .deleteEdge(edge, _), let .replaceEdge(_, edge):
            [
                "edge:\(edge.id.rawValue.uuidString)",
                "node:\(edge.from.rawValue.uuidString)",
                "node:\(edge.to.rawValue.uuidString)"
            ]
        case let .replaceChapter(before, _):
            ["chapter:\(before.id.rawValue.uuidString)"]
        case let .insertSetting(setting, _), let .deleteSetting(setting, _), let .replaceSetting(_, setting):
            ["setting:\(setting.id.rawValue.uuidString)"]
        default:
            []
        }
    }
}
