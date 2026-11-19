import Foundation
import Testing
@testable import CausalityCore

@Suite("AI 提案校验与采纳")
struct ProposalTests {
    private func script() -> ConvergenceDemo.Script {
        ConvergenceDemo.make()
    }

    private func proposal(
        _ payload: ProposalPayload,
        project: StoryProject,
        scope: ProposalScope,
        baseRevision: Int? = nil
    ) -> AIProposal {
        var nodeRevisions: [NodeID: Int] = [:]
        for nodeID in scope.editableNodeIDs {
            if let node = project.node(nodeID) {
                nodeRevisions[nodeID] = node.revision
            }
        }
        return AIProposal(
            baseRevision: baseRevision ?? project.revision,
            nodeRevisions: nodeRevisions,
            payload: payload
        )
    }

    // MARK: 最小改动

    @MainActor
    @Test("改一条分支时，另一条分支与结局都不受影响")
    func minimalBranchEdit() throws {
        let demo = script()
        let project = demo.project
        let scope = ProposalScope.selection(nodeID: demo.askTownsfolk, in: project)
        let arrivalEdge = try #require(
            project.edges.first { $0.from == demo.askTownsfolk && $0.to == demo.ending }
        )

        let payload = ProposalPayload(
            summary: "把公开追问改成更含蓄的相遇",
            changes: [
                ProposalChange(
                    target: .node,
                    id: demo.askTownsfolk.rawValue.uuidString,
                    body: "卖纸的老人没有招呼，只把同纹的纸推到阿禾手边。"
                ),
                ProposalChange(
                    target: .edge,
                    id: arrivalEdge.id.rawValue.uuidString,
                    label: "众人沉默地跟着阿禾往渡口走"
                ),
            ],
            notes: ["保留了群像结局，另一条守密分支未改动。"]
        )

        let validated = ProposalValidator.validate(
            proposal(payload, project: project, scope: scope),
            in: project,
            scope: scope
        )
        #expect(validated.status == .ready)
        #expect(validated.acceptedItems.count == 2)
        #expect(validated.rejectedItems.isEmpty)

        let editor = StoryEditor(project: project)
        let applied = try editor.adopt(validated)
        #expect(applied == 2)
        #expect(editor.project.node(demo.askTownsfolk)?.body.contains("同纹的纸") == true)
        #expect(editor.project.edge(arrivalEdge.id)?.label == "众人沉默地跟着阿禾往渡口走")
        // 另一条分支原样保留。
        #expect(editor.project.node(demo.keepSecret) == project.node(demo.keepSecret))
        // 结局正文只有一份。
        let rows = OutlineBuilder.build(project: editor.project).flatMap(\.rows)
        #expect(rows.filter { $0.nodeID == demo.ending && $0.role == .scene }.count == 1)

        #expect(try editor.undo())
        #expect(editor.project == project)
        #expect(editor.hasAdopted(validated.proposal.id) == false)
    }

    // MARK: 过时与冲突

    @MainActor
    @Test("项目版本变过，提案整体标为过期并拒绝采纳")
    func staleProposal() throws {
        let demo = script()
        var project = demo.project
        let scope = ProposalScope.selection(nodeID: demo.ending, in: project)
        let snapshot = project.revision

        // 作者在等待期间改了一句台词，项目版本随之前进。
        try ProjectEditing.apply(
            ProjectMutations.updateNode(demo.lantern, in: project) { $0.body += "（改）" },
            to: &project
        )
        project.revision += 1
        let payload = ProposalPayload(
            changes: [ProposalChange(target: .node, id: demo.ending.rawValue.uuidString, summary: "新摘要")]
        )
        let validated = ProposalValidator.validate(
            proposal(payload, project: project, scope: scope, baseRevision: snapshot),
            in: project,
            scope: scope
        )
        #expect(validated.status == .stale(base: snapshot, current: project.revision))

        let editor = StoryEditor(project: project)
        var caught: ProposalApplyError?
        do {
            _ = try editor.adopt(validated)
        } catch let error as ProposalApplyError {
            caught = error
        }
        #expect(caught != nil)
        #expect(editor.project == project)
    }

    @MainActor
    @Test("等待期间作者改过同一节点，标为冲突")
    func conflictOnEditedNode() throws {
        let demo = script()
        let project = demo.project
        let scope = ProposalScope.selection(nodeID: demo.ending, in: project)
        let snapshot = project.revision

        var stale: AIProposal = proposal(
            ProposalPayload(
                changes: [ProposalChange(target: .node, id: demo.ending.rawValue.uuidString, body: "AI 版本正文")]
            ),
            project: project,
            scope: scope,
            baseRevision: snapshot
        )
        // 模型返回的是旧节点版本。
        stale.nodeRevisions[demo.ending] = (project.node(demo.ending)?.revision ?? 0) - 1

        let validated = ProposalValidator.validate(stale, in: project, scope: scope)
        #expect(validated.status == .conflicted(["旧渡口的信"]))
        #expect(validated.acceptedOperations.isEmpty)

        let editor = StoryEditor(project: project)
        var caught: ProposalApplyError?
        do {
            _ = try editor.adopt(validated)
        } catch let error as ProposalApplyError {
            caught = error
        }
        #expect(caught == .conflicted(["旧渡口的信"]))
        #expect(editor.project == project)
    }

    // MARK: 锁定与范围

    @Test("锁定设定的改动只作为讨论建议")
    func lockedSettingBecomesSuggestion() throws {
        let demo = script()
        let project = demo.project
        let locked = try #require(project.settings.first { $0.isLocked })
        let scope = ProposalScope.selection(nodeID: demo.ending, in: project)

        let payload = ProposalPayload(
            changes: [ProposalChange(target: .setting, id: locked.id.rawValue.uuidString, text: "母亲欠的不是人情")]
        )
        let validated = ProposalValidator.validate(
            proposal(payload, project: project, scope: scope),
            in: project,
            scope: scope
        )
        #expect(validated.status == .ready)
        #expect(validated.acceptedItems.isEmpty)
        #expect(validated.suggestionItems.count == 1)
        #expect(validated.suggestionItems[0].outcome.explanation?.contains("锁定") == true)
        #expect(validated.isAdoptable == false)
    }

    @Test("超出范围的改动只作为建议")
    func outOfScopeBecomesSuggestion() throws {
        let demo = script()
        let project = demo.project
        let scope = ProposalScope.selection(nodeID: demo.askTownsfolk, in: project)

        let payload = ProposalPayload(
            changes: [ProposalChange(target: .node, id: demo.lantern.rawValue.uuidString, body: "重写开场")]
        )
        let validated = ProposalValidator.validate(
            proposal(payload, project: project, scope: scope),
            in: project,
            scope: scope
        )
        #expect(validated.items.count == 1)
        #expect(validated.items[0].outcome.explanation?.contains("超出") == true)
        #expect(validated.acceptedOperations.isEmpty)
    }

    // MARK: 部分失败

    @MainActor
    @Test("部分失败：坏的项被拒，好的项照常可采纳")
    func partialFailure() throws {
        let demo = script()
        let project = demo.project
        let scope = ProposalScope.selection(nodeID: demo.ending, in: project)

        let payload = ProposalPayload(
            nodes: [
                NodeDraft(
                    ref: "n_letter",
                    title: "回信",
                    kind: .event,
                    summary: "阿禾写下回信",
                    body: "她把回信折成灯形。",
                    characterNames: ["阿禾"],
                    placeNames: ["旧渡口"]
                )
            ],
            edges: [
                EdgeDraft(from: demo.ending.rawValue.uuidString, to: "n_letter", kind: .plain, label: "回信被放进河灯"),
                EdgeDraft(from: "n_letter", to: "n_missing", kind: .plain, label: "通往不存在的场景"),
            ]
        )
        let validated = ProposalValidator.validate(
            proposal(payload, project: project, scope: scope),
            in: project,
            scope: scope
        )
        #expect(validated.status == .ready)
        #expect(validated.acceptedItems.count == 2)
        #expect(validated.rejectedItems.count == 1)
        #expect(validated.rejectedItems[0].outcome.explanation?.contains("端点不存在") == true)

        let editor = StoryEditor(project: project)
        _ = try editor.adopt(validated)
        #expect(editor.project.nodes.count == project.nodes.count + 1)
        #expect(editor.project.edges.count == project.edges.count + 1)
        #expect(editor.project.nodes.contains { $0.title == "回信" })
    }

    // MARK: 幂等与成组

    @MainActor
    @Test("同一份提案只落地一次")
    func duplicateAdoption() throws {
        let demo = script()
        let project = demo.project
        let scope = ProposalScope.selection(nodeID: demo.ending, in: project)
        let payload = ProposalPayload(
            changes: [ProposalChange(target: .node, id: demo.ending.rawValue.uuidString, summary: "新的结局摘要")]
        )
        let validated = ProposalValidator.validate(
            proposal(payload, project: project, scope: scope),
            in: project,
            scope: scope
        )
        let editor = StoryEditor(project: project)
        _ = try editor.adopt(validated)

        var caught: ProposalApplyError?
        do {
            _ = try editor.adopt(validated)
        } catch let error as ProposalApplyError {
            caught = error
        }
        #expect(caught == .duplicate(validated.proposal.id))
        #expect(editor.project.node(demo.ending)?.summary == "新的结局摘要")
    }

    @MainActor
    @Test("新节点与它的出边落在同一组")
    func newNodeAndEdgeShareGroup() throws {
        let demo = script()
        let project = demo.project
        let scope = ProposalScope.selection(nodeID: demo.ending, in: project)
        let payload = ProposalPayload(
            nodes: [NodeDraft(ref: "n_after", title: "第二个结局", kind: .ending, body: "灯灭之后。")],
            edges: [EdgeDraft(from: demo.ending.rawValue.uuidString, to: "n_after", kind: .choice, label: "把信留下")]
        )
        let validated = ProposalValidator.validate(
            proposal(payload, project: project, scope: scope),
            in: project,
            scope: scope
        )
        #expect(validated.items.count == 2)
        let group = try #require(validated.groups.first { $0.itemIDs.count == 2 })
        #expect(group.adoptableItemIDs.count == 2)
    }

    @MainActor
    @Test("模型给了不认识的人物名，记一条说明但不阻断")
    func unknownCharacterIsNoted() throws {
        let demo = script()
        let project = demo.project
        let scope = ProposalScope.selection(nodeID: demo.ending, in: project)
        let payload = ProposalPayload(
            nodes: [NodeDraft(ref: "n_x", title: "桥上的人", characterNames: ["不存在的人"])]
        )
        let validated = ProposalValidator.validate(
            proposal(payload, project: project, scope: scope),
            in: project,
            scope: scope
        )
        #expect(validated.acceptedItems.count == 1)
        #expect(validated.notes.contains { $0.contains("不存在的人") })
        let editor = StoryEditor(project: project)
        _ = try editor.adopt(validated)
        let added = try #require(editor.project.nodes.first { $0.title == "桥上的人" })
        #expect(added.characterIDs.isEmpty)
    }

    // MARK: 解析

    @Test("从带说明文字与代码块的回复里取出 JSON")
    func jsonExtraction() throws {
        let fenced = """
        好的，这是提案：
        ```json
        {"summary": "整理", "nodes": [], "edges": [], "changes": [], "removals": [], "notes": ["保留结局"]}
        ```
        需要的话我再展开。
        """
        let payload = try ProposalParsing.decodePayload(from: fenced)
        #expect(payload.summary == "整理")
        #expect(payload.notes == ["保留结局"])

        let inline = "提案如下：{\"summary\":\"x\",\"nodes\":[],\"edges\":[],\"changes\":[],\"removals\":[],\"notes\":[]} 完。"
        #expect(try ProposalParsing.decodePayload(from: inline).summary == "x")

        let missing = "这次没有提案。"
        var caught: AIError?
        do {
            _ = try ProposalParsing.decodePayload(from: missing)
        } catch let error as AIError {
            caught = error
        }
        #expect(caught != nil)
    }

    @Test("结构化 schema 是合法 JSON，且严格模式要求的字段齐全")
    func schemaIsValidJSON() throws {
        let data = try #require(ProposalSchema.json.data(using: .utf8))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["additionalProperties"] as? Bool == false)
        let required = try #require(object["required"] as? [String])
        #expect(Set(required) == ["summary", "nodes", "edges", "changes", "removals", "notes"])
        let properties = try #require(object["properties"] as? [String: Any])
        #expect(Set(properties.keys) == Set(required))
    }

    @Test("上下文范围映射到可改范围")
    func scopeMapping() {
        let demo = script()
        let project = demo.project
        let request = ProposalRequest(
            kind: .editSelection,
            instruction: "x",
            contextScope: .selection,
            selection: demo.keepSecret,
            provider: .openCodeGo,
            model: "glm-5.3",
            credential: AICredential(apiKey: "test")
        )
        let selectionScope = ProposalService.makeScope(request: request, project: project)
        #expect(selectionScope.editableNodeIDs.contains(demo.keepSecret))
        #expect(selectionScope.editableNodeIDs.contains(demo.ending))
        #expect(selectionScope.allowRemovals == false)

        var chapterRequest = request
        chapterRequest.contextScope = .chapter
        let chapterScope = ProposalService.makeScope(request: chapterRequest, project: project)
        let chapterNodeCount = project.nodes.count { $0.chapterID == demo.chapterID }
        #expect(chapterScope.editableNodeIDs.count == chapterNodeCount)
        #expect(chapterScope.defaultChapterID == demo.chapterID)

        var projectRequest = request
        projectRequest.contextScope = .project
        let wholeScope = ProposalService.makeScope(request: projectRequest, project: project)
        #expect(wholeScope.editableEdgeIDs.count == project.edges.count)
        #expect(wholeScope.editableSettingIDs.isSubset(of: Set(project.settings.filter { !$0.isLocked }.map(\.id))))
    }

    // MARK: 上下文

    @Test("默认上下文带梗概、已确认设定与选中项相邻关系")
    func contextContents() throws {
        let demo = script()
        let project = demo.project
        let context = PromptBuilder.makeContext(
            kind: .editSelection,
            contextScope: .selection,
            selection: demo.ending,
            project: project
        )
        #expect(context.logline == project.logline)
        #expect(context.settings.allSatisfy { $0.isConfirmed })
        #expect(context.nodes.contains { $0.id == demo.ending })
        #expect(context.nodes.contains { $0.id == demo.keepSecret })
        #expect(context.nodes.contains { $0.id == demo.askTownsfolk })
        #expect(context.nodes.contains { $0.id == demo.lantern } == false)
        #expect(context.references.contains { $0.kind == .setting })
        #expect(context.assetCaptions.isEmpty)

        let message = PromptBuilder.userMessage(kind: .editSelection, context: context, instruction: "改得含蓄一点")
        #expect(message.contains("作者这一轮的要求"))
        #expect(message.contains("已锁定，不可改动"))
        #expect(message.contains(demo.ending.rawValue.uuidString))
    }

    @Test("排除的引用不进消息也不进引用列表")
    func excludedReference() throws {
        let demo = script()
        let project = demo.project
        let full = PromptBuilder.makeContext(
            kind: .editSelection,
            contextScope: .selection,
            selection: demo.ending,
            project: project
        )
        let settingReference = try #require(full.references.first { $0.kind == .setting })
        let trimmed = PromptBuilder.makeContext(
            kind: .editSelection,
            contextScope: .selection,
            selection: demo.ending,
            project: project,
            excluded: [settingReference.id]
        )
        #expect(trimmed.references.contains(settingReference) == false)
        let message = PromptBuilder.userMessage(kind: .editSelection, context: trimmed, instruction: "x")
        #expect(message.contains(settingReference.title) == false)
    }
}
