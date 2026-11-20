import Foundation

/// 设定、配图、讨论的落地实现。
extension EditOperation {
    func applySettingChange(to project: inout StoryProject) throws {
        switch self {
        case let .insertSetting(value, index):
            guard !project.settings.contains(where: { $0.id == value.id }) else {
                throw EditError.duplicateID(CoreText.format("事实设定 %@", String(describing: value.id)))
            }
            project.settings.insert(value, at: clamped(index, project.settings.count))

        case let .deleteSetting(value, _):
            guard let position = project.settings.firstIndex(where: { $0.id == value.id }) else {
                throw EditError.settingNotFound(value.id)
            }
            guard !project.settings[position].isLocked else {
                throw EditError.lockedSetting(value.id)
            }
            project.settings.remove(at: position)
            for nodeIndex in project.nodes.indices {
                project.nodes[nodeIndex].settingIDs.removeAll { $0 == value.id }
            }

        case let .replaceSetting(before, after):
            guard let position = project.settings.firstIndex(where: { $0.id == before.id }) else {
                throw EditError.settingNotFound(before.id)
            }
            // 锁定策略在 ProjectMutations 与 AI 提案校验层。
            // 这里只做机械落地，撤销需要能还原任何一步。
            var normalized = after
            normalized.normalize()
            project.settings[position] = normalized

        default:
            throw EditError.invalidOperation(CoreText.format("事实设定操作收到 %@", String(describing: self)))
        }
    }

    func applyAssetChange(to project: inout StoryProject) throws {
        switch self {
        case let .insertAsset(value, index):
            guard !project.assets.contains(where: { $0.id == value.id }) else {
                throw EditError.duplicateID(CoreText.format("配图 %@", String(describing: value.id)))
            }
            project.assets.insert(value, at: clamped(index, project.assets.count))

        case let .deleteAsset(value, _):
            guard let position = project.assets.firstIndex(where: { $0.id == value.id }) else {
                throw EditError.assetNotFound(value.id)
            }
            project.assets.remove(at: position)
            for nodeIndex in project.nodes.indices where project.nodes[nodeIndex].coverAssetID == value.id {
                project.nodes[nodeIndex].coverAssetID = nil
            }

        case let .replaceAsset(before, after):
            guard let position = project.assets.firstIndex(where: { $0.id == before.id }) else {
                throw EditError.assetNotFound(before.id)
            }
            project.assets[position] = after

        default:
            throw EditError.invalidOperation(CoreText.format("配图操作收到 %@", String(describing: self)))
        }
    }

    func applyDiscussionChange(to project: inout StoryProject) throws {
        switch self {
        case let .insertDiscussion(value, index):
            guard !project.discussions.contains(where: { $0.id == value.id }) else {
                throw EditError.duplicateID(CoreText.format("讨论 %@", String(describing: value.id)))
            }
            project.discussions.insert(value, at: clamped(index, project.discussions.count))

        case let .deleteDiscussion(value, _):
            guard let position = project.discussions.firstIndex(where: { $0.id == value.id }) else {
                throw EditError.discussionNotFound(value.id)
            }
            project.discussions.remove(at: position)

        case let .replaceDiscussion(before, after):
            guard let position = project.discussions.firstIndex(where: { $0.id == before.id }) else {
                throw EditError.discussionNotFound(before.id)
            }
            project.discussions[position] = after

        default:
            throw EditError.invalidOperation(CoreText.format("讨论操作收到 %@", String(describing: self)))
        }
    }
}
