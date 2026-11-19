import Foundation
import Testing
@testable import CausalityCore

@Suite("章节故事板")
struct StoryboardTests {
    /// 三张卡的一章：A、B、C（按作者编排的顺序）。
    private func threeCardProject() -> (project: StoryProject, chapterID: ChapterID, ids: [NodeID]) {
        var builder = ProjectBuilder(seed: 41, title: "故事板")
        let chapterID = builder.project.chapters[0].id
        var ids: [NodeID] = []
        for title in ["阿禾捡到河灯", "她去找梁婆婆", "梁婆婆认出河灯"] {
            ids.append(builder.addNode(title: title, chapterID: chapterID, isEntry: ids.isEmpty))
        }
        builder.connect(ids[0], to: ids[1], kind: .plain, label: "接下来")
        builder.connect(ids[1], to: ids[2], kind: .cause, label: "只有她认得那盏灯")
        return (builder.finalized(), chapterID, ids)
    }

    @Test("插在两张卡之间，顺序与状态都对")
    func insertBetweenCards() {
        let demo = threeCardProject()
        var project = demo.project

        let idea = StoryNode(status: .idea, title: "她是怎么认出母亲笔迹的？", chapterID: demo.chapterID)
        let operations = ProjectMutations.insertCard(idea, in: demo.chapterID, at: 1, in: project)
        try? ProjectEditing.apply(operations, to: &project)

        let chapter = project.chapter(demo.chapterID)
        #expect(chapter?.order == [demo.ids[0], idea.id, demo.ids[1], demo.ids[2]])
        #expect(project.node(idea.id)?.status == .idea)
        #expect(project.node(idea.id)?.chapterID == demo.chapterID)
        // 原有连线不受影响。
        #expect(project.edges.count == 2)
    }

    @Test("念头留在板上，不进大纲；写成正式场景后才出现")
    func ideaCardStaysOffOutline() throws {
        let demo = threeCardProject()
        var project = demo.project
        let idea = StoryNode(status: .idea, title: "她是怎么认出母亲笔迹的？", chapterID: demo.chapterID)
        try ProjectEditing.apply(ProjectMutations.insertCard(idea, in: demo.chapterID, at: 1, in: project), to: &project)

        let before = OutlineBuilder.build(project: project).flatMap(\.rows)
        #expect(before.count == 3)
        #expect(before.contains { $0.nodeID == idea.id } == false)

        try ProjectEditing.apply(
            ProjectMutations.updateNode(idea.id, in: project) { $0.status = .draft },
            to: &project
        )
        let after = OutlineBuilder.build(project: project).flatMap(\.rows)
        #expect(after.contains { $0.nodeID == idea.id })
        #expect(after.count == 4)
    }

    @Test("跨章拖卡片，正文与连线都跟着走")
    func moveAcrossChaptersKeepsEdges() throws {
        let demo = threeCardProject()
        var project = demo.project
        let second = Chapter(title: "第二章")
        try ProjectEditing.apply(ProjectMutations.appendChapter(second, to: project), to: &project)

        try ProjectEditing.apply(
            ProjectMutations.moveCard(demo.ids[1], toChapter: second.id, at: 0, in: project),
            to: &project
        )

        #expect(project.node(demo.ids[1])?.chapterID == second.id)
        #expect(project.chapter(second.id)?.order == [demo.ids[1]])
        #expect(project.chapter(demo.chapterID)?.order == [demo.ids[0], demo.ids[2]])
        // 连线一条没丢，循环仍成立。
        #expect(project.edges.count == 2)
        #expect(project.edges.contains { $0.from == demo.ids[0] && $0.to == demo.ids[1] })
        #expect(project.edges.contains { $0.from == demo.ids[1] && $0.to == demo.ids[2] })
        // 正文指标只属于这张卡。
        #expect(project.node(demo.ids[1])?.title == "她去找梁婆婆")
    }

    @Test("AI 在缝隙补卡：默认落在锚点之后")
    @MainActor
    func aiInsertionLandsAtGap() throws {
        let demo = threeCardProject()
        let project = demo.project
        let scope = ProposalScope.insertion(chapterID: demo.chapterID, index: 1, in: project)

        var revisions: [NodeID: Int] = [:]
        for nodeID in scope.editableNodeIDs {
            if let node = project.node(nodeID) { revisions[nodeID] = node.revision }
        }
        let proposal = AIProposal(
            baseRevision: project.revision,
            nodeRevisions: revisions,
            payload: ProposalPayload(
                summary: "补一场认出笔迹的戏",
                nodes: [
                    NodeDraft(
                        ref: "n_handwriting",
                        title: "她是怎么认出母亲笔迹的？",
                        kind: .event,
                        summary: "灯底的笔画歪了一下，她认出那是母亲握笔的习惯。",
                        characterNames: ["阿禾"]
                    )
                ]
            )
        )

        let validated = ProposalValidator.validate(proposal, in: project, scope: scope)
        #expect(validated.status == .ready)
        #expect(validated.acceptedItems.count == 1)

        let editor = StoryEditor(project: project)
        _ = try editor.adopt(validated)
        let order = editor.project.chapter(demo.chapterID)?.order ?? []
        #expect(order.count == 4)
        #expect(order[0] == demo.ids[0])
        #expect(order[2] == demo.ids[1])
        #expect(editor.project.nodes.count == 4)

        // 撤销回退整张卡。
        #expect(try editor.undo())
        #expect(editor.project == project)
    }

    @Test("插在章首时也能落位")
    @MainActor
    func aiInsertionAtChapterStart() throws {
        let demo = threeCardProject()
        let project = demo.project
        let scope = ProposalScope.insertion(chapterID: demo.chapterID, index: 0, in: project)
        let proposal = AIProposal(
            baseRevision: project.revision,
            payload: ProposalPayload(nodes: [NodeDraft(ref: "n_head", title: "开场前一晚")])
        )
        let validated = ProposalValidator.validate(proposal, in: project, scope: scope)
        let editor = StoryEditor(project: project)
        _ = try editor.adopt(validated)
        #expect(editor.project.chapter(demo.chapterID)?.order.first == editor.project.nodes.first { $0.title == "开场前一晚" }?.id)
    }

    @Test("提示词里写清楚插在哪")
    func promptMentionsInsertion() {
        let demo = threeCardProject()
        let context = PromptBuilder.makeContext(
            kind: .insertCard,
            contextScope: .selection,
            selection: demo.ids[0],
            project: demo.project,
            insertion: CardInsertionPoint(chapterID: demo.chapterID, index: 1, anchorNodeID: demo.ids[0])
        )
        let message = PromptBuilder.userMessage(
            kind: .insertCard,
            context: context,
            instruction: "补一场让阿禾认出笔迹的戏"
        )
        #expect(message.contains("【插入位置】"))
        #expect(message.contains("新卡插在「阿禾捡到河灯」之后"))
        #expect(PromptBuilder.systemPrompt(for: .insertCard).contains("只新增一张卡"))
    }

    @Test("范围内只包含缝隙两侧的卡")
    func insertionScopeNeighbours() {
        let demo = threeCardProject()
        let scope = ProposalScope.insertion(chapterID: demo.chapterID, index: 1, in: demo.project)
        #expect(scope.editableNodeIDs.contains(demo.ids[0]))
        #expect(scope.editableNodeIDs.contains(demo.ids[1]))
        #expect(scope.defaultInsertAfter == demo.ids[0])
        #expect(scope.defaultInsertIndex == 1)
        #expect(scope.allowRemovals == false)
    }

    @Test("同列往下拖，落点要跳过自己")
    func dropIndexAdjustment() {
        #expect(ProjectMutations.dropIndex(currentIndex: 0, gapIndex: 2) == 1)
        #expect(ProjectMutations.dropIndex(currentIndex: 2, gapIndex: 0) == 0)
        #expect(ProjectMutations.dropIndex(currentIndex: nil, gapIndex: 3) == 3)
    }
}
