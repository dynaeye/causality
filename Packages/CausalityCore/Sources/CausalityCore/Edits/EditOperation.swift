import Foundation

public enum EditError: Error, CustomStringConvertible, Equatable {
    case nodeNotFound(NodeID)
    case edgeNotFound(EdgeID)
    case chapterNotFound(ChapterID)
    case characterNotFound(CharacterID)
    case placeNotFound(PlaceID)
    case settingNotFound(SettingID)
    case assetNotFound(AssetID)
    case discussionNotFound(DiscussionID)
    case duplicateID(String)
    case invalidOperation(String)
    case lockedSetting(SettingID)

    public var description: String {
        switch self {
        case let .nodeNotFound(id): "节点不存在：\(id)"
        case let .edgeNotFound(id): "发展线不存在：\(id)"
        case let .chapterNotFound(id): "章节不存在：\(id)"
        case let .characterNotFound(id): "人物不存在：\(id)"
        case let .placeNotFound(id): "地点不存在：\(id)"
        case let .settingNotFound(id): "设定不存在：\(id)"
        case let .assetNotFound(id): "配图不存在：\(id)"
        case let .discussionNotFound(id): "讨论不存在：\(id)"
        case let .duplicateID(what): "标识重复：\(what)"
        case let .invalidOperation(reason): "操作非法：\(reason)"
        case let .lockedSetting(id): "设定已锁定，不能改动：\(id)"
        }
    }
}

/// 最小编辑单元。所有修改经它提交，因此撤销、保存和 AI 采纳共用一条路径。
public enum EditOperation: Sendable, Equatable {
    case insertNode(StoryNode, index: Int)
    case deleteNode(StoryNode, index: Int)
    case replaceNode(before: StoryNode, after: StoryNode)

    case insertEdge(StoryEdge, index: Int)
    case deleteEdge(StoryEdge, index: Int)
    case replaceEdge(before: StoryEdge, after: StoryEdge)

    case insertChapter(Chapter, index: Int)
    case deleteChapter(Chapter, index: Int)
    case replaceChapter(before: Chapter, after: Chapter)

    case insertCharacter(StoryCharacter, index: Int)
    case deleteCharacter(StoryCharacter, index: Int)
    case replaceCharacter(before: StoryCharacter, after: StoryCharacter)

    case insertPlace(StoryPlace, index: Int)
    case deletePlace(StoryPlace, index: Int)
    case replacePlace(before: StoryPlace, after: StoryPlace)

    case insertSetting(Setting, index: Int)
    case deleteSetting(Setting, index: Int)
    case replaceSetting(before: Setting, after: Setting)

    case insertAsset(Asset, index: Int)
    case deleteAsset(Asset, index: Int)
    case replaceAsset(before: Asset, after: Asset)

    case insertDiscussion(Discussion, index: Int)
    case deleteDiscussion(Discussion, index: Int)
    case replaceDiscussion(before: Discussion, after: Discussion)

    case replaceAuditWaivers(before: [AuditWaiver], after: [AuditWaiver])
    case replaceThreads(before: [StoryThread], after: [StoryThread])

    case setCanvasPoint(NodeID, before: CanvasPoint?, after: CanvasPoint?)
    case setCharacterCanvasPoint(CharacterID, before: CanvasPoint?, after: CanvasPoint?)
    case setHeader(before: ProjectHeader, after: ProjectHeader)
    case setCardGroupOverride(NodeID, before: String?, after: String?)

    public var inverse: EditOperation {
        switch self {
        case let .insertNode(node, index): .deleteNode(node, index: index)
        case let .deleteNode(node, index): .insertNode(node, index: index)
        case let .replaceNode(before, after): .replaceNode(before: after, after: before)

        case let .insertEdge(edge, index): .deleteEdge(edge, index: index)
        case let .deleteEdge(edge, index): .insertEdge(edge, index: index)
        case let .replaceEdge(before, after): .replaceEdge(before: after, after: before)

        case let .insertChapter(chapter, index): .deleteChapter(chapter, index: index)
        case let .deleteChapter(chapter, index): .insertChapter(chapter, index: index)
        case let .replaceChapter(before, after): .replaceChapter(before: after, after: before)

        case let .insertCharacter(value, index): .deleteCharacter(value, index: index)
        case let .deleteCharacter(value, index): .insertCharacter(value, index: index)
        case let .replaceCharacter(before, after): .replaceCharacter(before: after, after: before)

        case let .insertPlace(value, index): .deletePlace(value, index: index)
        case let .deletePlace(value, index): .insertPlace(value, index: index)
        case let .replacePlace(before, after): .replacePlace(before: after, after: before)

        case let .insertSetting(value, index): .deleteSetting(value, index: index)
        case let .deleteSetting(value, index): .insertSetting(value, index: index)
        case let .replaceSetting(before, after): .replaceSetting(before: after, after: before)

        case let .insertAsset(value, index): .deleteAsset(value, index: index)
        case let .deleteAsset(value, index): .insertAsset(value, index: index)
        case let .replaceAsset(before, after): .replaceAsset(before: after, after: before)

        case let .insertDiscussion(value, index): .deleteDiscussion(value, index: index)
        case let .deleteDiscussion(value, index): .insertDiscussion(value, index: index)
        case let .replaceDiscussion(before, after): .replaceDiscussion(before: after, after: before)

        case let .replaceAuditWaivers(before, after): .replaceAuditWaivers(before: after, after: before)
        case let .replaceThreads(before, after): .replaceThreads(before: after, after: before)

        case let .setCanvasPoint(nodeID, before, after): .setCanvasPoint(nodeID, before: after, after: before)
        case let .setCharacterCanvasPoint(id, before, after): .setCharacterCanvasPoint(id, before: after, after: before)
        case let .setHeader(before, after): .setHeader(before: after, after: before)
        case let .setCardGroupOverride(id, before, after): .setCardGroupOverride(id, before: after, after: before)
        }
    }

    public func apply(to project: inout StoryProject) throws {
        switch self {
        case .insertNode, .deleteNode, .replaceNode:
            try applyNodeChange(to: &project)
        case .insertEdge, .deleteEdge, .replaceEdge:
            try applyEdgeChange(to: &project)
        case .insertChapter, .deleteChapter, .replaceChapter:
            try applyChapterChange(to: &project)
        case .insertCharacter, .deleteCharacter, .replaceCharacter:
            try applyCharacterChange(to: &project)
        case .insertPlace, .deletePlace, .replacePlace:
            try applyPlaceChange(to: &project)
        case .insertSetting, .deleteSetting, .replaceSetting:
            try applySettingChange(to: &project)
        case .insertAsset, .deleteAsset, .replaceAsset:
            try applyAssetChange(to: &project)
        case .insertDiscussion, .deleteDiscussion, .replaceDiscussion:
            try applyDiscussionChange(to: &project)
        case let .replaceAuditWaivers(before, after):
            guard project.auditWaivers == before else {
                throw EditError.invalidOperation("体检忽略列表已变化")
            }
            project.auditWaivers = after
        case let .setCanvasPoint(nodeID, _, after):
            if let after {
                project.canvas[nodeID] = after
            } else {
                project.canvas[nodeID] = nil
            }
        case let .setCharacterCanvasPoint(characterID, _, after):
            if let after {
                project.characterCanvas[characterID] = after
            } else {
                project.characterCanvas[characterID] = nil
            }
        case let .setHeader(_, after):
            project.title = after.title
            project.logline = after.logline
        case let .replaceThreads(before, after):
            guard project.threads == before else {
                throw EditError.invalidOperation("线索列表已变化")
            }
            project.threads = after
        case let .setCardGroupOverride(id, _, after):
            if let after {
                project.cardGroupOverrides[id.rawValue.uuidString] = after
            } else {
                project.cardGroupOverrides[id.rawValue.uuidString] = nil
            }
        }
    }
}

/// 只包含项目头部的可撤销改动。
public struct ProjectHeader: Sendable, Equatable {
    public var title: String
    public var logline: String

    public init(title: String, logline: String) {
        self.title = title
        self.logline = logline
    }

    public init(project: StoryProject) {
        self.title = project.title
        self.logline = project.logline
    }
}

public enum ProjectEditing {
    /// 顺序应用一组操作。任一步失败时，已应用的部分会回滚。
    public static func apply(_ operations: [EditOperation], to project: inout StoryProject) throws {
        var working = project
        for operation in operations {
            try operation.apply(to: &working)
        }
        project = working
    }

    /// 撤销一组操作：反向、逆序。
    public static func revert(_ operations: [EditOperation], in project: inout StoryProject) throws {
        try apply(operations.reversed().map(\.inverse), to: &project)
    }

    public static func inverse(of operations: [EditOperation], in project: StoryProject) throws -> [EditOperation] {
        var working = project
        var inverses: [EditOperation] = []
        for operation in operations {
            try operation.apply(to: &working)
            inverses.append(operation.inverse)
        }
        return inverses.reversed()
    }
}
