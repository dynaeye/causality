import Foundation

/// 设定、配图、讨论与项目头的意图级操作。
extension ProjectMutations {
    // MARK: 设定

    public static func appendSetting(_ setting: Setting, to project: StoryProject) -> [EditOperation] {
        var value = setting
        value.normalize()
        return [.insertSetting(value, index: project.settings.count)]
    }

    public static func updateSetting(
        _ id: SettingID,
        in project: StoryProject,
        _ body: (inout Setting) -> Void
    ) -> [EditOperation] {
        guard var after = project.setting(id) else { return [] }
        let before = after
        body(&after)
        after.normalize()
        guard after != before else { return [] }
        after.revision = before.revision + 1
        after.modifiedAt = Timestamp.now()
        return [.replaceSetting(before: before, after: after)]
    }

    public static func setSettingConfirmed(_ id: SettingID, _ confirmed: Bool, in project: StoryProject) -> [EditOperation] {
        updateSetting(id, in: project) { setting in
            setting.isConfirmed = confirmed
            if !confirmed { setting.isLocked = false }
        }
    }

    public static func setSettingLocked(_ id: SettingID, _ locked: Bool, in project: StoryProject) -> [EditOperation] {
        updateSetting(id, in: project) { setting in
            setting.isLocked = locked
            if locked { setting.isConfirmed = true }
        }
    }

    /// 挂载要两边都写：设定记节点，节点也记设定。
    /// 大纲、导出、AI 上下文读的是节点那侧的 `settingIDs`，只写一边就会「挂上了却看不见」。
    public static func attachSetting(_ settingID: SettingID, to nodeID: NodeID, in project: StoryProject) -> [EditOperation] {
        var operations = updateSetting(settingID, in: project) { setting in
            if !setting.attachedNodeIDs.contains(nodeID) {
                setting.attachedNodeIDs.append(nodeID)
            }
        }
        operations += updateNode(nodeID, in: project) { node in
            if !node.settingIDs.contains(settingID) {
                node.settingIDs.append(settingID)
            }
        }
        return operations
    }

    public static func detachSetting(_ settingID: SettingID, from nodeID: NodeID, in project: StoryProject) -> [EditOperation] {
        guard let setting = project.setting(settingID), !setting.isLocked else { return [] }
        var operations = updateSetting(settingID, in: project) { value in
            value.attachedNodeIDs.removeAll { $0 == nodeID }
        }
        operations += updateNode(nodeID, in: project) { node in
            node.settingIDs.removeAll { $0 == settingID }
        }
        return operations
    }

    public static func deleteSetting(_ id: SettingID, in project: StoryProject) throws -> [EditOperation] {
        guard let setting = project.setting(id) else { return [] }
        guard !setting.isLocked else { throw EditError.lockedSetting(id) }
        let index = project.settings.firstIndex { $0.id == id } ?? (project.settings.count - 1)
        return [.deleteSetting(setting, index: index)]
    }

    // MARK: 配图

    public static func appendAsset(_ asset: Asset, to project: StoryProject) -> [EditOperation] {
        [.insertAsset(asset, index: project.assets.count)]
    }

    public static func attachCover(_ assetID: AssetID, to nodeID: NodeID, in project: StoryProject) -> [EditOperation] {
        updateNode(nodeID, in: project) { $0.coverAssetID = assetID }
    }

    // MARK: 讨论

    public static func appendDiscussion(_ discussion: Discussion, to project: StoryProject) -> [EditOperation] {
        [.insertDiscussion(discussion, index: project.discussions.count)]
    }

    public static func appendMessage(
        _ message: Message,
        to discussionID: DiscussionID,
        in project: StoryProject
    ) -> [EditOperation] {
        guard let before = project.discussions.first(where: { $0.id == discussionID }) else { return [] }
        var after = before
        after.messages.append(message)
        after.updatedAt = Timestamp.now()
        return [.replaceDiscussion(before: before, after: after)]
    }

    /// 清空一条讨论的历史消息；保留讨论本身、锚点和引用材料。可以用撤销恢复。
    public static func clearMessages(
        in discussionID: DiscussionID,
        in project: StoryProject
    ) -> [EditOperation] {
        guard let before = project.discussions.first(where: { $0.id == discussionID }),
              !before.messages.isEmpty else { return [] }
        var after = before
        after.messages = []
        after.updatedAt = Timestamp.now()
        return [.replaceDiscussion(before: before, after: after)]
    }

    public static func setReferences(
        _ references: [DiscussionReference],
        for discussionID: DiscussionID,
        in project: StoryProject
    ) -> [EditOperation] {
        guard let before = project.discussions.first(where: { $0.id == discussionID }) else { return [] }
        var after = before
        after.references = references
        after.updatedAt = Timestamp.now()
        return [.replaceDiscussion(before: before, after: after)]
    }

    // MARK: 项目头

    public static func updateHeader(
        title: String? = nil,
        logline: String? = nil,
        in project: StoryProject
    ) -> [EditOperation] {
        let before = ProjectHeader(project: project)
        let after = ProjectHeader(
            title: title ?? before.title,
            logline: logline ?? before.logline
        )
        guard after != before else { return [] }
        return [.setHeader(before: before, after: after)]
    }
}
