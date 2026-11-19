import Foundation

/// 面向作者意图的操作生成器。每个意图展开成一组最小编辑，保证撤销一次退回原样。
public enum ProjectMutations {
    // MARK: 章节

    public static func appendChapter(_ chapter: Chapter, to project: StoryProject) -> [EditOperation] {
        [.insertChapter(chapter, index: project.chapters.count)]
    }

    /// 改章节标题或说明。
    public static func updateChapter(
        _ id: ChapterID,
        in project: StoryProject,
        _ body: (inout Chapter) -> Void
    ) -> [EditOperation] {
        guard var after = project.chapter(id) else { return [] }
        let before = after
        body(&after)
        guard after != before else { return [] }
        return [.replaceChapter(before: before, after: after)]
    }

    public static func deleteChapter(_ id: ChapterID, in project: StoryProject) -> [EditOperation] {
        guard let chapter = project.chapter(id) else { return [] }
        var operations: [EditOperation] = []
        var working = project
        // 章里的卡一起删。一张卡只属于一章，留在库里就会变成画布上看得见、却删不掉的幽灵。
        for nodeID in project.nodes.filter({ $0.chapterID == id }).map(\.id) {
            let nodeOperations = deleteNode(nodeID, in: working)
            guard !nodeOperations.isEmpty else { continue }
            operations += nodeOperations
            try? ProjectEditing.apply(nodeOperations, to: &working)
        }
        let chapterIndex = working.chapters.firstIndex { $0.id == id } ?? (working.chapters.count - 1)
        operations.append(.deleteChapter(working.chapter(id) ?? chapter, index: chapterIndex))
        return operations
    }

    // MARK: 节点

    /// 新节点进项目，同时进入所属章的顺序表末尾。
    public static func appendNode(_ node: StoryNode, to project: StoryProject) -> [EditOperation] {
        var operations: [EditOperation] = [.insertNode(node, index: project.nodes.count)]
        if let chapterID = node.chapterID, let chapter = project.chapter(chapterID) {
            var after = chapter
            after.order.append(node.id)
            operations.append(.replaceChapter(before: chapter, after: after))
        }
        return operations
    }

    /// 在章内第 index 张之前插一张卡。新卡默认是留在板上的念头。
    public static func insertCard(
        _ node: StoryNode,
        in chapterID: ChapterID,
        at index: Int,
        in project: StoryProject
    ) -> [EditOperation] {
        var card = node
        card.chapterID = chapterID
        var working = project
        var operations = appendNode(card, to: working)
        try? ProjectEditing.apply(operations, to: &working)
        let moveOperations = moveNode(card.id, toChapter: chapterID, at: index, in: working)
        try? ProjectEditing.apply(moveOperations, to: &working)
        operations += moveOperations
        return operations
    }

    /// 把卡片放到缝隙 index 时，卡片移走后的真实落点。
    public static func dropIndex(currentIndex: Int?, gapIndex: Int) -> Int {
        guard let currentIndex, currentIndex < gapIndex else { return gapIndex }
        return gapIndex - 1
    }

    /// 把卡片移到另一章或同章的另一位置。连线与正文都跟着卡片走。
    public static func moveCard(
        _ id: NodeID,
        toChapter chapterID: ChapterID,
        at index: Int,
        in project: StoryProject
    ) -> [EditOperation] {
        moveNode(id, toChapter: chapterID, at: index, in: project)
    }

    public static func deleteNode(_ id: NodeID, in project: StoryProject) -> [EditOperation] {
        guard let node = project.node(id) else { return [] }
        var operations: [EditOperation] = []

        // 按索引倒序删除，撤销时反向即为升序插入，连线顺序能原样复原。
        let touchingEdges = project.edges.enumerated()
            .filter { $0.element.from == id || $0.element.to == id }
            .reversed()
        for (index, edge) in touchingEdges {
            operations.append(.deleteEdge(edge, index: index))
        }

        // 锁定设定只解除挂载，设定本身保留。
        for setting in project.settings where setting.attachedNodeIDs.contains(id) {
            var after = setting
            after.attachedNodeIDs.removeAll { $0 == id }
            operations.append(.replaceSetting(before: setting, after: after))
        }

        for discussion in project.discussions where discussion.anchorNodeID == id {
            var after = discussion
            after.anchorNodeID = nil
            operations.append(.replaceDiscussion(before: discussion, after: after))
        }

        for chapter in project.chapters where chapter.order.contains(id) {
            var after = chapter
            after.order.removeAll { $0 == id }
            operations.append(.replaceChapter(before: chapter, after: after))
        }

        if let point = project.canvas[id] {
            operations.append(.setCanvasPoint(id, before: point, after: nil))
        }
        let nodeIndex = project.nodes.firstIndex { $0.id == id } ?? (project.nodes.count - 1)
        operations.append(.deleteNode(node, index: nodeIndex))
        return operations
    }

    public static func updateNode(
        _ id: NodeID,
        in project: StoryProject,
        _ body: (inout StoryNode) -> Void
    ) -> [EditOperation] {
        guard var after = project.node(id) else { return [] }
        let before = after
        body(&after)
        guard after != before else { return [] }
        after.revision = before.revision + 1
        after.modifiedAt = Timestamp.now()
        return [.replaceNode(before: before, after: after)]
    }

    /// 移动节点到另一章，或在同章内调整同级顺序。
    public static func moveNode(
        _ id: NodeID,
        toChapter chapterID: ChapterID?,
        at targetIndex: Int?,
        in project: StoryProject
    ) -> [EditOperation] {
        guard let node = project.node(id) else { return [] }
        var operations: [EditOperation] = []

        for chapter in project.chapters where chapter.order.contains(id) {
            var after = chapter
            after.order.removeAll { $0 == id }
            operations.append(.replaceChapter(before: chapter, after: after))
        }

        var updatedNode = node
        if node.chapterID != chapterID {
            updatedNode.chapterID = chapterID
            updatedNode.revision += 1
            updatedNode.modifiedAt = Timestamp.now()
            operations.append(.replaceNode(before: node, after: updatedNode))
        }

        if let chapterID, let chapter = project.chapter(chapterID) {
            var after = chapter
            after.order.removeAll { $0 == id }
            let index = min(max(targetIndex ?? after.order.count, 0), after.order.count)
            after.order.insert(id, at: index)
            operations.append(.replaceChapter(before: chapter, after: after))
        }

        return operations
    }

    public static func reorderNode(_ id: NodeID, toIndex: Int, in project: StoryProject) -> [EditOperation] {
        guard let node = project.node(id), let chapterID = node.chapterID else { return [] }
        return moveNode(id, toChapter: chapterID, at: toIndex, in: project)
    }

    public static func setEntry(_ id: NodeID, isEntry: Bool, in project: StoryProject) -> [EditOperation] {
        updateNode(id, in: project) { $0.isEntry = isEntry }
    }

    public static func setCanvasPoint(
        _ point: CanvasPoint?,
        for id: NodeID,
        in project: StoryProject
    ) -> [EditOperation] {
        let before = project.canvas[id]
        guard before != point else { return [] }
        return [.setCanvasPoint(id, before: before, after: point)]
    }

    /// 并列组的手动覆盖：`ownGroup` / `mergeAbove`，传 nil 恢复自动。
    public static func setCardGroupOverride(
        _ id: NodeID,
        value: String?,
        in project: StoryProject
    ) -> [EditOperation] {
        let key = id.rawValue.uuidString
        let before = project.cardGroupOverrides[key]
        guard before != value else { return [] }
        return [.setCardGroupOverride(id, before: before, after: value)]
    }

    // MARK: 线索

    public static func appendThread(_ thread: StoryThread, to project: StoryProject) -> [EditOperation] {
        guard !project.threads.contains(where: { $0.id == thread.id }) else { return [] }
        return [.replaceThreads(before: project.threads, after: project.threads + [thread])]
    }

    public static func updateThread(
        _ id: ThreadID,
        in project: StoryProject,
        _ body: (inout StoryThread) -> Void
    ) -> [EditOperation] {
        guard let index = project.threads.firstIndex(where: { $0.id == id }) else { return [] }
        var threads = project.threads
        body(&threads[index])
        guard threads != project.threads else { return [] }
        return [.replaceThreads(before: project.threads, after: threads)]
    }

    public static func deleteThread(_ id: ThreadID, in project: StoryProject) -> [EditOperation] {
        let threads = project.threads.filter { $0.id != id }
        guard threads.count != project.threads.count else { return [] }
        return [.replaceThreads(before: project.threads, after: threads)]
    }

    /// 同一个场景在同一条线索上同一个角色只记一次。
    public static func addThreadEntry(
        _ entry: ThreadEntry,
        threadID: ThreadID,
        in project: StoryProject
    ) -> [EditOperation] {
        guard project.node(entry.nodeID) != nil,
              let thread = project.threads.first(where: { $0.id == threadID }),
              !thread.entries.contains(where: { $0.nodeID == entry.nodeID && $0.role == entry.role }) else {
            return []
        }
        return updateThread(threadID, in: project) { $0.entries.append(entry) }
    }

    public static func removeThreadEntry(
        _ entryID: UUID,
        threadID: ThreadID,
        in project: StoryProject
    ) -> [EditOperation] {
        updateThread(threadID, in: project) { $0.entries.removeAll { $0.id == entryID } }
    }

    // MARK: 体检忽略

    /// 忽略一条体检问题；同规则同一个对象只记一次。
    public static func addAuditWaiver(_ waiver: AuditWaiver, to project: StoryProject) -> [EditOperation] {
        guard !project.auditWaivers.contains(where: { $0.waiverKey == waiver.waiverKey }) else {
            return []
        }
        return [.replaceAuditWaivers(before: project.auditWaivers, after: project.auditWaivers + [waiver])]
    }

    public static func removeAuditWaiver(_ id: UUID, in project: StoryProject) -> [EditOperation] {
        let after = project.auditWaivers.filter { $0.id != id }
        guard after.count != project.auditWaivers.count else { return [] }
        return [.replaceAuditWaivers(before: project.auditWaivers, after: after)]
    }

    // MARK: 发展线

    public static func connect(
        from: NodeID,
        to: NodeID,
        kind: EdgeKind,
        label: String,
        condition: String = "",
        annotation: String = "",
        in project: StoryProject
    ) -> [EditOperation] {
        guard project.node(from) != nil, project.node(to) != nil else { return [] }
        let edge = StoryEdge(
            from: from,
            to: to,
            kind: kind,
            label: label,
            condition: condition,
            annotation: annotation
        )
        return [.insertEdge(edge, index: project.edges.count)]
    }

    public static func updateEdge(
        _ id: EdgeID,
        in project: StoryProject,
        _ body: (inout StoryEdge) -> Void
    ) -> [EditOperation] {
        guard let before = project.edge(id) else { return [] }
        var after = before
        body(&after)
        guard after != before else { return [] }
        return [.replaceEdge(before: before, after: after)]
    }

    public static func disconnect(_ id: EdgeID, in project: StoryProject) -> [EditOperation] {
        guard let edge = project.edge(id),
              let index = project.edges.firstIndex(where: { $0.id == id }) else { return [] }
        return [.deleteEdge(edge, index: index)]
    }

    /// 把一个选择点的主线去向指到这条边。同一个起点的其它边自动取消主线标记。
    public static func setMainline(_ id: EdgeID, in project: StoryProject) -> [EditOperation] {
        guard let edge = project.edge(id) else { return [] }
        var operations: [EditOperation] = []
        for other in project.edges where other.from == edge.from && other.id != edge.id && other.isMainline {
            operations += updateEdge(other.id, in: project) { $0.isMainline = false }
        }
        operations += updateEdge(id, in: project) { $0.isMainline = true }
        return operations
    }

    /// 取消主线标记：之后按第一条出边推导。
    public static func clearMainline(_ id: EdgeID, in project: StoryProject) -> [EditOperation] {
        updateEdge(id, in: project) { $0.isMainline = false }
    }

    // MARK: 人物、地点

    public static func appendCharacter(_ value: StoryCharacter, to project: StoryProject) -> [EditOperation] {
        [.insertCharacter(value, index: project.characters.count)]
    }

    public static func setCharacterCanvasPoint(
        _ point: CanvasPoint?,
        for id: CharacterID,
        in project: StoryProject
    ) -> [EditOperation] {
        let before = project.characterCanvas[id]
        guard before != point else { return [] }
        return [.setCharacterCanvasPoint(id, before: before, after: point)]
    }

    public static func appendPlace(_ value: StoryPlace, to project: StoryProject) -> [EditOperation] {
        [.insertPlace(value, index: project.places.count)]
    }

    public static func updateCharacter(
        _ id: CharacterID,
        in project: StoryProject,
        _ body: (inout StoryCharacter) -> Void
    ) -> [EditOperation] {
        guard let before = project.characters.first(where: { $0.id == id }) else { return [] }
        var after = before
        body(&after)
        guard after != before else { return [] }
        return [.replaceCharacter(before: before, after: after)]
    }

    public static func addRelation(
        _ kind: RelationKind,
        from id: CharacterID,
        to target: CharacterID,
        in project: StoryProject
    ) -> [EditOperation] {
        guard id != target else { return [] }
        return updateCharacter(id, in: project) { character in
            guard !character.relations.contains(where: { $0.kind == kind && $0.target == target }) else { return }
            character.relations.append(CharacterRelation(kind: kind, target: target))
        }
    }

    public static func removeRelation(
        _ relationID: UUID,
        from id: CharacterID,
        in project: StoryProject
    ) -> [EditOperation] {
        updateCharacter(id, in: project) { character in
            character.relations.removeAll { $0.id == relationID }
        }
    }

    /// 删人物会同时把出场关系从所有场景上摘掉，场景本身保留。
    public static func deleteCharacter(_ id: CharacterID, in project: StoryProject) -> [EditOperation] {
        guard let character = project.characters.first(where: { $0.id == id }) else { return [] }
        let index = project.characters.firstIndex { $0.id == id } ?? project.characters.count - 1
        return [.deleteCharacter(character, index: index)]
    }

    public static func updatePlace(
        _ id: PlaceID,
        in project: StoryProject,
        _ body: (inout StoryPlace) -> Void
    ) -> [EditOperation] {
        guard let before = project.places.first(where: { $0.id == id }) else { return [] }
        var after = before
        body(&after)
        guard after != before else { return [] }
        return [.replacePlace(before: before, after: after)]
    }
}
