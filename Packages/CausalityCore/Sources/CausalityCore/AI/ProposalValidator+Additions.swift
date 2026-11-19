import Foundation

/// 新增节点的落地与校验。
extension ProposalBuilder {
    // MARK: 新增

    mutating func applyNodeDraft(_ draft: NodeDraft) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            appendReject(.addNode, title: CoreText.text("（无标题）"), reason: CoreText.text("标题为空"), group: draft.ref)
            return
        }
        guard scope.allowNewNodes else {
            appendSuggestion(.addNode, title: title, reason: CoreText.text("当前范围不允许新增场景"), group: draft.ref)
            return
        }
        guard !draft.ref.trimmingCharacters(in: .whitespaces).isEmpty else {
            appendReject(.addNode, title: title, reason: CoreText.text("缺少提案内引用名 ref"), group: title)
            return
        }
        guard refMap[draft.ref] == nil else {
            appendReject(.addNode, title: title, reason: CoreText.format("ref %@ 重复", draft.ref), group: draft.ref)
            return
        }

        let chapterID = scope.defaultChapterID ?? project.chapters.first?.id
        guard let chapterID, working.chapter(chapterID) != nil else {
            appendReject(.addNode, title: title, reason: CoreText.text("项目里还没有可落章的章节"), group: draft.ref)
            return
        }

        let node = makeNode(from: draft, title: title, chapterID: chapterID)

        var operations = apply(ProjectMutations.appendNode(node, to: working))
        if let index = insertionIndex(for: draft, chapterID: chapterID) {
            operations += apply(ProjectMutations.moveNode(node.id, toChapter: chapterID, at: index, in: working))
        }

        commitApplied(
            .addNode,
            title: title,
            detail: [
                FieldDiff(field: CoreText.text("类型"), before: "", after: draft.kind.displayName),
                FieldDiff(field: CoreText.text("摘要"), before: "", after: draft.summary),
                FieldDiff(field: CoreText.text("正文"), before: "", after: draft.body)
            ],
            operations: operations,
            group: draft.ref
        )
        refMap[draft.ref] = node.id
    }

    mutating func makeNode(from draft: NodeDraft, title: String, chapterID: ChapterID) -> StoryNode {
        var node = StoryNode(
            kind: draft.kind,
            title: title,
            summary: draft.summary,
            body: draft.body,
            chapterID: chapterID,
            isEntry: working.nodes.isEmpty
        )
        node.characterIDs = resolveCharacters(draft.characterNames, nodeTitle: title)
        node.placeIDs = resolvePlaces(draft.placeNames, nodeTitle: title)
        node.settingIDs = resolveSettings(draft.settingTitles, nodeTitle: title)
        return node
    }

    mutating func applyEdgeDraft(_ draft: EdgeDraft) {
        guard scope.allowNewEdges else {
            appendSuggestion(.addEdge, title: "\(draft.from) → \(draft.to)", reason: CoreText.text("当前范围不允许新增发展线"), group: draft.from)
            return
        }
        guard let from = resolve(draft.from), let to = resolve(draft.to) else {
            appendReject(
                .addEdge,
                title: "\(draft.from) → \(draft.to)",
                reason: CoreText.format("端点不存在：%@", resolve(draft.from) == nil ? draft.from : draft.to),
                group: draft.from
            )
            return
        }
        guard from != to else {
            appendReject(.addEdge, title: draft.label, reason: CoreText.text("不允许自环"), group: draft.from)
            return
        }
        let sourceTitle = working.node(from)?.title ?? draft.from
        let targetTitle = working.node(to)?.title ?? draft.to
        let operations = ProjectMutations.connect(
            from: from,
            to: to,
            kind: draft.kind,
            label: draft.label,
            condition: draft.condition,
            in: working
        )
        commit(
            .addEdge,
            title: "\(sourceTitle) → \(targetTitle)",
            detail: [
                FieldDiff(field: CoreText.text("类型"), before: "", after: draft.kind.displayName),
                FieldDiff(field: CoreText.text("文字"), before: "", after: draft.label),
                FieldDiff(field: CoreText.text("条件"), before: "", after: draft.condition)
            ],
            operations: operations,
            group: draft.from
        )
}
}
