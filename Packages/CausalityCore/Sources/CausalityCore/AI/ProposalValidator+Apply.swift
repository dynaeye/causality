import Foundation

/// 修改与移除的落地与校验。
extension ProposalBuilder {
    // MARK: 修改

    mutating func applyChange(_ change: ProposalChange) {
        switch change.target {
        case .node: applyNodeChange(change)
        case .edge: applyEdgeChange(change)
        case .setting: applySettingChange(change)
        }
    }

    mutating func applyNodeChange(_ change: ProposalChange) {
        guard let nodeID = NodeID(string: change.id), let before = working.node(nodeID) else {
            appendReject(.changeNode, title: change.id, reason: CoreText.text("场景不存在"), group: change.id)
            return
        }
        guard scope.contains(nodeID: nodeID) else {
            appendSuggestion(.changeNode, title: before.title, reason: CoreText.text("超出本次范围"), group: change.id)
            return
        }
        if !touchedNodeIDs.contains(nodeID),
           let expected = proposal.nodeRevisions[nodeID],
           expected != before.revision {
            conflicts.append(before.title)
            appendReject(.changeNode, title: before.title, reason: CoreText.text("等待回复期间作者改过这一场景"), group: change.id)
            return
        }
        touchedNodeIDs.insert(nodeID)

        var after = before
        var diffs: [FieldDiff] = []
        if let title = change.title, title != before.title {
            after.title = title
            diffs.append(FieldDiff(field: CoreText.text("标题"), before: before.title, after: title))
        }
        if let summary = change.summary, summary != before.summary {
            after.summary = summary
            diffs.append(FieldDiff(field: CoreText.text("摘要"), before: before.summary, after: summary))
        }
        if let body = change.body, body != before.body {
            after.body = body
            diffs.append(FieldDiff(field: CoreText.text("正文"), before: before.body, after: body))
        }
        if let kind = change.nodeKind, kind != before.kind {
            after.kind = kind
            diffs.append(FieldDiff(field: CoreText.text("类型"), before: before.kind.displayName, after: kind.displayName))
        }
        guard !diffs.isEmpty else {
            notes.append(CoreText.format("场景「%@」的修改与原稿相同，已忽略。", before.title))
            return
        }
        guard !after.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendReject(.changeNode, title: before.title, reason: CoreText.text("标题不能为空"), group: change.id)
            return
        }

        let operations = ProjectMutations.updateNode(nodeID, in: working) { value in
            value.title = after.title
            value.summary = after.summary
            value.body = after.body
            value.kind = after.kind
        }
        commit(.changeNode, title: before.title, detail: diffs, operations: operations, group: change.id)
    }

    mutating func applyEdgeChange(_ change: ProposalChange) {
        guard let edgeID = EdgeID(string: change.id), let before = working.edge(edgeID) else {
            appendReject(.changeEdge, title: change.id, reason: CoreText.text("发展线不存在"), group: change.id)
            return
        }
        guard scope.contains(edgeID: edgeID) || (scope.contains(nodeID: before.from) && scope.contains(nodeID: before.to)) else {
            appendSuggestion(.changeEdge, title: before.label, reason: CoreText.text("超出本次范围"), group: change.id)
            return
        }

        var diffs: [FieldDiff] = []
        if let label = change.label, label != before.label {
            diffs.append(FieldDiff(field: CoreText.text("文字"), before: before.label, after: label))
        }
        if let condition = change.condition, condition != before.condition {
            diffs.append(FieldDiff(field: CoreText.text("条件"), before: before.condition, after: condition))
        }
        if let kind = change.edgeKind, kind != before.kind {
            diffs.append(FieldDiff(field: CoreText.text("类型"), before: before.kind.displayName, after: kind.displayName))
        }
        guard !diffs.isEmpty else { return }

        let operations = ProjectMutations.updateEdge(edgeID, in: working) { value in
            if let label = change.label { value.label = label }
            if let condition = change.condition { value.condition = condition }
            if let kind = change.edgeKind { value.kind = kind }
        }
        let title = working.node(before.from)?.title ?? "…"
        commit(.changeEdge, title: CoreText.format("%@ 的出边", title), detail: diffs, operations: operations, group: change.id)
    }

    mutating func applySettingChange(_ change: ProposalChange) {
        guard let settingID = SettingID(string: change.id), let before = working.setting(settingID) else {
            appendReject(.changeSetting, title: change.id, reason: CoreText.text("事实设定不存在"), group: change.id)
            return
        }
        guard !before.isLocked else {
            appendSuggestion(.changeSetting, title: before.title, reason: CoreText.text("事实设定已锁定，只能作为讨论建议"), group: change.id)
            return
        }
        guard scope.contains(settingID: settingID) else {
            appendSuggestion(.changeSetting, title: before.title, reason: CoreText.text("超出本次范围"), group: change.id)
            return
        }

        var diffs: [FieldDiff] = []
        if let text = change.text, text != before.text {
            diffs.append(FieldDiff(field: CoreText.text("事实设定内容"), before: before.text, after: text))
        }
        if let title = change.title, title != before.title {
            diffs.append(FieldDiff(field: CoreText.text("标题"), before: before.title, after: title))
        }
        guard !diffs.isEmpty else { return }

        let operations = ProjectMutations.updateSetting(settingID, in: working) { value in
            if let text = change.text { value.text = text }
            if let title = change.title { value.title = title }
        }
        commit(.changeSetting, title: before.title, detail: diffs, operations: operations, group: change.id)
    }

    // MARK: 移除

    mutating func applyRemoval(_ removal: ProposalRemoval) {
        switch removal.target {
        case .node:
            guard let nodeID = NodeID(string: removal.id), let node = working.node(nodeID) else {
                appendReject(.removeNode, title: removal.id, reason: CoreText.text("场景不存在"), group: removal.id)
                return
            }
            guard scope.allowRemovals, scope.contains(nodeID: nodeID) else {
                appendSuggestion(.removeNode, title: node.title, reason: CoreText.text("当前范围不允许移除"), group: removal.id)
                return
            }
            let operations = ProjectMutations.deleteNode(nodeID, in: working)
            commit(
                .removeNode,
                title: node.title,
                detail: [FieldDiff(field: "场景", before: node.title, after: CoreText.text("（移除）"))],
                operations: operations,
                group: removal.id
            )

        case .edge:
            guard let edgeID = EdgeID(string: removal.id), let edge = working.edge(edgeID) else {
                appendReject(.removeEdge, title: removal.id, reason: CoreText.text("发展线不存在"), group: removal.id)
                return
            }
            guard scope.allowRemovals, scope.contains(edgeID: edgeID) else {
                appendSuggestion(.removeEdge, title: edge.label, reason: CoreText.text("当前范围不允许移除"), group: removal.id)
                return
            }
            let operations = ProjectMutations.disconnect(edgeID, in: working)
            commit(
                .removeEdge,
                title: edge.label.isEmpty ? "发展线" : edge.label,
                detail: [FieldDiff(field: CoreText.text("发展线"), before: edge.label, after: CoreText.text("（移除）"))],
                operations: operations,
                group: removal.id
            )

        case .setting:
            guard let settingID = SettingID(string: removal.id), let setting = working.setting(settingID) else {
                appendReject(.removeSetting, title: removal.id, reason: CoreText.text("事实设定不存在"), group: removal.id)
                return
            }
            guard !setting.isLocked else {
                appendSuggestion(.removeSetting, title: setting.title, reason: CoreText.text("事实设定已锁定，不能移除"), group: removal.id)
                return
            }
            guard let operations = try? ProjectMutations.deleteSetting(settingID, in: working) else {
                appendReject(.removeSetting, title: setting.title, reason: CoreText.text("移除失败"), group: removal.id)
                return
            }
            commit(
                .removeSetting,
                title: setting.title,
                detail: [FieldDiff(field: "事实设定", before: setting.title, after: CoreText.text("（移除）"))],
                operations: operations,
                group: removal.id
            )
        }
}
}
