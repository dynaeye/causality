import Foundation
import Testing
@testable import CausalityCore

@Suite("按组采纳与建议分组")
struct ProposalGroupAdoptionTests {
    private func script() -> ConvergenceDemo.Script { ConvergenceDemo.make() }

    /// 两条互不相干的改动：各改一张卡，彼此不共享节点，分成两组。
    private func twoBranchProposal(
        _ demo: ConvergenceDemo.Script,
        project: StoryProject
    ) throws -> (ValidatedProposal, NodeID, NodeID) {
        let payload = ProposalPayload(
            summary: "两条分支各改一张卡",
            changes: [
                ProposalChange(
                    target: .node,
                    id: demo.keepSecret.rawValue.uuidString,
                    body: "守密的人把信压在灯下"
                ),
                ProposalChange(
                    target: .node,
                    id: demo.askTownsfolk.rawValue.uuidString,
                    body: "众人把河灯抬到渡口"
                ),
            ]
        )
        let scope = ProposalScope.chapter(project.chapters[0].id, in: project)
        let validated = ProposalValidator.validate(
            AIProposal(baseRevision: project.revision, nodeRevisions: [:], payload: payload),
            in: project,
            scope: scope
        )
        return (validated, demo.keepSecret, demo.askTownsfolk)
    }

    @MainActor
    @Test("按组采纳只落这一组，另一组还能再采纳")
    func adoptByGroup() throws {
        let demo = script()
        let project = demo.project
        let (validated, secretNode, townsfolkNode) = try twoBranchProposal(demo, project: project)
        #expect(validated.status == .ready)
        #expect(validated.groups.count == 2)

        let editor = StoryEditor(project: project)
        let first = try #require(validated.groups.first { $0.adoptableItemIDs.count == 1 })

        let count = try editor.adopt(validated, itemIDs: first.adoptableItemIDs)
        #expect(count == 1)
        #expect(editor.adoptedItems(of: validated.proposal.id) == Set(first.adoptableItemIDs))

        let remaining = validated.acceptedItems
            .map(\.id)
            .filter { !editor.adoptedItems(of: validated.proposal.id).contains($0) }
        #expect(remaining.count == 1)
        #expect(try editor.adopt(validated, itemIDs: remaining) == 1)

        // 两条都落地后，再采纳一次就没有可落的项。
        var caught: ProposalApplyError?
        do {
            _ = try editor.adopt(validated)
        } catch let error as ProposalApplyError {
            caught = error
        }
        #expect(caught == .duplicate(validated.proposal.id))

        #expect(editor.project.node(secretNode)?.body == "守密的人把信压在灯下")
        #expect(editor.project.node(townsfolkNode)?.body == "众人把河灯抬到渡口")
    }

    @MainActor
    @Test("撤回收回这一组，其余组不受影响")
    func undoOneGroup() throws {
        let demo = script()
        let project = demo.project
        let (validated, secretNode, _) = try twoBranchProposal(demo, project: project)
        let editor = StoryEditor(project: project)

        let itemID = try #require(
            validated.items.first { item in
                item.operations.contains { operation in
                    if case let .replaceNode(before, _) = operation { return before.id == secretNode }
                    return false
                }
            }?.id
        )
        _ = try editor.adopt(validated, itemIDs: [itemID])
        #expect(editor.project.node(secretNode)?.body == "守密的人把信压在灯下")

        #expect(try editor.undo())
        #expect(editor.project.node(secretNode)?.body == project.node(secretNode)?.body)
        #expect(editor.adoptedItems(of: validated.proposal.id).isEmpty)
    }

    @MainActor
    @Test("锁定的事实设定只能当建议，单独成组且不可采纳")
    func lockedSettingsGoToSuggestionGroup() throws {
        let demo = script()
        var project = demo.project
        let locked = try #require(project.settings.first)
        try ProjectEditing.apply(
            ProjectMutations.setSettingLocked(locked.id, true, in: project),
            to: &project
        )

        let payload = ProposalPayload(
            summary: "改一条锁定的设定",
            changes: [
                ProposalChange(
                    target: .setting,
                    id: locked.id.rawValue.uuidString,
                    text: "这条不该被改掉"
                )
            ]
        )
        let scope = ProposalScope.chapter(project.chapters[0].id, in: project)
        let validated = ProposalValidator.validate(
            AIProposal(baseRevision: project.revision, nodeRevisions: [:], payload: payload),
            in: project,
            scope: scope
        )

        let suggestionGroup = try #require(validated.groups.first { $0.id == "suggestions" })
        #expect(suggestionGroup.title.contains("只能作为建议"))
        #expect(suggestionGroup.adoptableItemIDs.isEmpty)
        #expect(validated.suggestionItems.count == 1)
        #expect(validated.acceptedItems.isEmpty)
    }
}
