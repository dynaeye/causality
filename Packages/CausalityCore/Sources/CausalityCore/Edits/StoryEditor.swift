import Foundation
import Observation

/// 一次可撤销的修改。
public struct UndoEntry: Sendable, Equatable {
    public let name: String
    public let forward: [EditOperation]
    public let backward: [EditOperation]
    public let time: Date
    public let coalescingKey: String?
    /// 撤销时一并还原项目头的时间与版本号，保证“撤销后与原稿逐字段一致”。
    /// 这笔修改来自哪份 AI 提案。撤销时要把提案放回可采纳状态。
    public let proposalID: UUID?
    public let revisionBefore: Int
    public let revisionAfter: Int
    public let modifiedAtBefore: Date
    public let modifiedAtAfter: Date
}

/// 唯一编辑入口。所有修改经这里提交，因此撤销、保存与 AI 采纳共用同一条路径。
@MainActor
@Observable
public final class StoryEditor {
    public private(set) var project: StoryProject

    /// 每份提案已经落地了哪几项，按组采纳时靠它防重复。
    @ObservationIgnored private var adoptedProposalItems: [UUID: Set<String>] = [:]
    @ObservationIgnored private var undoEntries: [UndoEntry] = []
    @ObservationIgnored private var redoEntries: [UndoEntry] = []
    @ObservationIgnored private let coalescingWindow: TimeInterval

    public init(project: StoryProject, coalescingWindow: TimeInterval = 1.5) {
        self.project = project
        self.coalescingWindow = coalescingWindow
    }

    public var canUndo: Bool { !undoEntries.isEmpty }
    public var canRedo: Bool { !redoEntries.isEmpty }
    public var undoActionName: String? { undoEntries.last?.name }
    public var redoActionName: String? { redoEntries.last?.name }
    public var undoDepth: Int { undoEntries.count }

    /// 提交一组编辑。整组进出一致，失败时项目保持原样。
    public func apply(
        _ operations: [EditOperation],
        name: String,
        coalescingKey: String? = nil,
        proposalID: UUID? = nil
    ) throws {
        guard !operations.isEmpty else { return }

        var working = project
        try ProjectEditing.apply(operations, to: &working)
        let backward = try ProjectEditing.inverse(of: operations, in: project)

        let revisionBefore = project.revision
        let modifiedAtBefore = project.modifiedAt
        let modifiedAtAfter = Timestamp.now()

        working.revision = revisionBefore + 1
        working.modifiedAt = modifiedAtAfter
        project = working

        let entry = UndoEntry(
            name: name,
            forward: operations,
            backward: backward,
            time: modifiedAtAfter,
            coalescingKey: coalescingKey,
            proposalID: proposalID,
            revisionBefore: revisionBefore,
            revisionAfter: working.revision,
            modifiedAtBefore: modifiedAtBefore,
            modifiedAtAfter: modifiedAtAfter
        )
        redoEntries.removeAll()
        push(entry)
    }

    @discardableResult
    public func undo() throws -> Bool {
        guard let entry = undoEntries.popLast() else { return false }
        try ProjectEditing.apply(entry.backward, to: &project)
        if let proposalID = entry.proposalID {
            adoptedProposalItems.removeValue(forKey: proposalID)
        }
        project.revision = entry.revisionBefore
        project.modifiedAt = entry.modifiedAtBefore
        redoEntries.append(entry)
        return true
    }

    @discardableResult
    public func redo() throws -> Bool {
        guard let entry = redoEntries.popLast() else { return false }
        try ProjectEditing.apply(entry.forward, to: &project)
        project.revision = entry.revisionAfter
        project.modifiedAt = entry.modifiedAtAfter
        undoEntries.append(entry)
        return true
    }

    /// 打开另一个版本（重新载入、或采纳 AI 提案后重置历史）。
    public func replaceProject(_ project: StoryProject, keepingHistory: Bool = false) {
        self.project = project
        if !keepingHistory {
            undoEntries.removeAll()
            redoEntries.removeAll()
            adoptedProposalItems.removeAll()
        }
    }

    /// 一组采纳作为一笔撤销。已存在的撤销栈保留。
    public func adopt(_ operations: [EditOperation], name: String) throws {
        try apply(operations, name: name)
    }

    /// 采纳一份校验过的提案：整份一次撤销；同一份提案的同一项只落地一次。
    ///
    /// 给 `itemIDs` 就只采纳这几项（按组采纳），没给的项下次还能采纳。
    @discardableResult
    public func adopt(_ validated: ValidatedProposal, itemIDs: [String]? = nil) throws -> Int {
        switch validated.status {
        case .ready:
            break
        case let .stale(base, current):
            throw ProposalApplyError.stale(base: base, current: current)
        case let .conflicted(titles):
            throw ProposalApplyError.conflicted(titles)
        }

        let already = adoptedProposalItems[validated.proposal.id] ?? []
        let remaining = validated.acceptedItems.filter { !already.contains($0.id) }
        let chosen: [ProposalItem]
        if let itemIDs {
            let wanted = Set(itemIDs)
            chosen = remaining.filter { wanted.contains($0.id) }
        } else {
            chosen = remaining
        }
        guard !chosen.isEmpty else { throw ProposalApplyError.duplicate(validated.proposal.id) }

        let operations = chosen.flatMap(\.operations)
        guard !operations.isEmpty else { throw ProposalApplyError.empty }
        let name = chosen.count == remaining.count ? "采纳 AI 提案" : "采纳 AI 提案（\(chosen.count) 项）"
        try apply(operations, name: name, proposalID: validated.proposal.id)
        adoptedProposalItems[validated.proposal.id, default: []].formUnion(chosen.map(\.id))
        return chosen.count
    }

    public func hasAdopted(_ proposalID: UUID) -> Bool {
        adoptedProposalItems[proposalID] != nil
    }

    /// 这份提案里已经落地的项，界面用来标「已采纳」。
    public func adoptedItems(of proposalID: UUID) -> Set<String> {
        adoptedProposalItems[proposalID] ?? []
    }

    private func push(_ entry: UndoEntry) {
        if let coalescingKey = entry.coalescingKey,
           var last = undoEntries.popLast(),
           last.coalescingKey == coalescingKey,
           entry.time.timeIntervalSince(last.time) <= coalescingWindow {
            last = UndoEntry(
                name: entry.name,
                forward: last.forward + entry.forward,
                backward: entry.backward + last.backward,
                time: entry.time,
                coalescingKey: coalescingKey,
                proposalID: last.proposalID,
                revisionBefore: last.revisionBefore,
                revisionAfter: entry.revisionAfter,
                modifiedAtBefore: last.modifiedAtBefore,
                modifiedAtAfter: entry.modifiedAtAfter
            )
            undoEntries.append(last)
        } else {
            undoEntries.append(entry)
        }
    }
}
