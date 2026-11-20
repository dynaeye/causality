import Foundation

// MARK: - 节点

public enum NodeKind: String, Codable, Sendable, CaseIterable, Hashable {
    case event
    case choice
    case ending

    public var displayName: String {
        switch self {
        case .event: "事件"
        case .choice: "选择点"
        case .ending: "结局"
        }
    }
}

public enum NodeStatus: String, Codable, Sendable, CaseIterable, Hashable {
    /// 正式场景，属于某一章。
    case draft
    /// 独立灵感卡，尚未接入故事。
    case idea

    public var displayName: String {
        switch self {
        case .draft: "场景"
        case .idea: "灵感卡"
        }
    }
}

/// 场景类型。策划与编剧共用的粗分类，不参与推导。
public enum SceneType: String, Codable, Sendable, CaseIterable, Hashable {
    case dialogue
    case cutscene
    case exploration
    case puzzle
    case combat
    case boss
    case montage

    public var displayName: String {
        switch self {
        case .dialogue: "对话"
        case .cutscene: "过场"
        case .exploration: "探索"
        case .puzzle: "解谜"
        case .combat: "战斗"
        case .boss: "首领"
        case .montage: "蒙太奇"
        }
    }
}

/// 写作完成度。与 `NodeStatus`（正式场景 / 念头）是两根轴，别混。
public enum WritingState: String, Codable, Sendable, CaseIterable, Hashable {
    case todo
    case drafting
    case revising
    case final

    public var displayName: String {
        switch self {
        case .todo: "待写"
        case .drafting: "在写"
        case .revising: "待改"
        case .final: "定稿"
        }
    }
}

/// 故事节点。正文全项目只有一份，章节与大纲顺序独立存储。
public struct StoryNode: Codable, Sendable, Identifiable, Hashable {
    public var id: NodeID
    public var kind: NodeKind
    public var status: NodeStatus
    public var title: String
    public var summary: String
    public var body: String
    /// 主章。灵感卡可以为空。
    public var chapterID: ChapterID?
    /// 多入口：该节点是故事入口。
    public var isEntry: Bool
    public var characterIDs: [CharacterID]
    public var placeIDs: [PlaceID]
    public var settingIDs: [SettingID]
    public var coverAssetID: AssetID?
    public var annotation: String
    // MARK: 场景工程字段（v2a）
    /// 视角人物。
    public var pov: CharacterID?
    /// 故事里的时间，人话写法（「第三日黄昏」）。
    public var storyTimeLabel: String
    public var sceneType: SceneType?
    /// 张力 1...5。
    public var tension: Int?
    /// 目标字数。
    public var targetWords: Int?
    public var writingState: WritingState?
    public var createdAt: Date
    public var modifiedAt: Date
    /// 内容版本号。AI 提案按它判断作者是否在等待期间改过同一节点。
    public var revision: Int

    public init(
        id: NodeID = NodeID(),
        kind: NodeKind = .event,
        status: NodeStatus = .draft,
        title: String,
        summary: String = "",
        body: String = "",
        chapterID: ChapterID? = nil,
        isEntry: Bool = false,
        characterIDs: [CharacterID] = [],
        placeIDs: [PlaceID] = [],
        settingIDs: [SettingID] = [],
        coverAssetID: AssetID? = nil,
        annotation: String = "",
        pov: CharacterID? = nil,
        storyTimeLabel: String = "",
        sceneType: SceneType? = nil,
        tension: Int? = nil,
        targetWords: Int? = nil,
        writingState: WritingState? = nil,
        createdAt: Date = Timestamp.now(),
        modifiedAt: Date = Timestamp.now(),
        revision: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.summary = summary
        self.body = body
        self.chapterID = chapterID
        self.isEntry = isEntry
        self.characterIDs = characterIDs
        self.placeIDs = placeIDs
        self.settingIDs = settingIDs
        self.coverAssetID = coverAssetID
        self.annotation = annotation
        self.pov = pov
        self.storyTimeLabel = storyTimeLabel
        self.sceneType = sceneType
        self.tension = tension
        self.targetWords = targetWords
        self.writingState = writingState
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.revision = revision
    }

    /// 手写解码：v2a 之后的字段缺失时补空，v1 的旧包直接能开。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(NodeID.self, forKey: .id)
        kind = try container.decodeIfPresent(NodeKind.self, forKey: .kind) ?? .event
        status = try container.decodeIfPresent(NodeStatus.self, forKey: .status) ?? .draft
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        chapterID = try container.decodeIfPresent(ChapterID.self, forKey: .chapterID)
        isEntry = try container.decodeIfPresent(Bool.self, forKey: .isEntry) ?? false
        characterIDs = try container.decodeIfPresent([CharacterID].self, forKey: .characterIDs) ?? []
        placeIDs = try container.decodeIfPresent([PlaceID].self, forKey: .placeIDs) ?? []
        settingIDs = try container.decodeIfPresent([SettingID].self, forKey: .settingIDs) ?? []
        coverAssetID = try container.decodeIfPresent(AssetID.self, forKey: .coverAssetID)
        annotation = try container.decodeIfPresent(String.self, forKey: .annotation) ?? ""
        pov = try container.decodeIfPresent(CharacterID.self, forKey: .pov)
        storyTimeLabel = try container.decodeIfPresent(String.self, forKey: .storyTimeLabel) ?? ""
        sceneType = try container.decodeIfPresent(SceneType.self, forKey: .sceneType)
        tension = try container.decodeIfPresent(Int.self, forKey: .tension)
        targetWords = try container.decodeIfPresent(Int.self, forKey: .targetWords)
        writingState = try container.decodeIfPresent(WritingState.self, forKey: .writingState)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Timestamp.now()
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Timestamp.now()
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    }
}

// MARK: - 发展线（边）

/// 覆盖简报里的四种连线：因为、选项、条件、接下来。
public enum EdgeKind: String, Codable, Sendable, CaseIterable, Hashable {
    case cause
    case choice
    case condition
    case plain

    public var displayName: String {
        switch self {
        case .cause: "因为"
        case .choice: "选项"
        case .condition: "条件"
        case .plain: "接下来"
        }
    }

    /// 大纲与 Markdown 共用的前缀，保证两种输出一致。
    public var markdownPrefix: String {
        switch self {
        case .cause: "因为"
        case .choice: "选项"
        case .condition: "条件"
        case .plain: "接下来"
        }
    }
}

/// 一条发展线。选项原文、条件文字和目标都挂在边上。
public struct StoryEdge: Codable, Sendable, Identifiable, Hashable {
    public var id: EdgeID
    public var from: NodeID
    public var to: NodeID
    public var kind: EdgeKind
    /// 选项原文 / 原因文字 / 进入条件 / 连接说明。
    public var label: String
    /// 附加条件文字。为空表示无条件。
    public var condition: String
    public var annotation: String
    /// 这个选择点选它当主线去向。同一个起点最多一条；不标就按第一条出边算。
    public var isMainline: Bool

    public init(
        id: EdgeID = EdgeID(),
        from: NodeID,
        to: NodeID,
        kind: EdgeKind = .plain,
        label: String = "",
        condition: String = "",
        annotation: String = "",
        isMainline: Bool = false
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.kind = kind
        self.label = label
        self.condition = condition
        self.annotation = annotation
        self.isMainline = isMainline
    }

    /// 手写解码：旧工程包里没有 isMainline，缺失就当支线。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(EdgeID.self, forKey: .id)
        from = try container.decode(NodeID.self, forKey: .from)
        to = try container.decode(NodeID.self, forKey: .to)
        kind = try container.decodeIfPresent(EdgeKind.self, forKey: .kind) ?? .plain
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        condition = try container.decodeIfPresent(String.self, forKey: .condition) ?? ""
        annotation = try container.decodeIfPresent(String.self, forKey: .annotation) ?? ""
        isMainline = try container.decodeIfPresent(Bool.self, forKey: .isMainline) ?? false
    }
}

// MARK: - 章节

public struct Chapter: Codable, Sendable, Identifiable, Hashable {
    public var id: ChapterID
    public var title: String
    public var summary: String
    /// 章内同级顺序表。大纲拖动修改这份顺序，缩进与汇合由推导得出。
    public var order: [NodeID]
    public var isCollapsedOnCanvas: Bool
    public var createdAt: Date

    public init(
        id: ChapterID = ChapterID(),
        title: String,
        summary: String = "",
        order: [NodeID] = [],
        isCollapsedOnCanvas: Bool = false,
        createdAt: Date = Timestamp.now()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.order = order
        self.isCollapsedOnCanvas = isCollapsedOnCanvas
        self.createdAt = createdAt
    }
}

// MARK: - 人物与地点

/// 亲属与亲友关系。存一份有向记录，反向的称呼由 App 推导。
public enum RelationKind: String, Codable, Sendable, CaseIterable, Hashable {
    case father
    case mother
    case child
    case elderBrother
    case youngerBrother
    case elderSister
    case youngerSister
    case sibling
    case grandparent
    case spouse
    case lover
    case friend
    case mentor
    case student
    case rival
    case enemy
    case other

    public var displayName: String {
        switch self {
        case .father: "父亲"
        case .mother: "母亲"
        case .child: "子女"
        case .elderBrother: "兄"
        case .youngerBrother: "弟"
        case .elderSister: "姐"
        case .youngerSister: "妹"
        case .sibling: "兄弟姐妹"
        case .grandparent: "祖辈"
        case .spouse: "夫妻"
        case .lover: "恋人"
        case .friend: "朋友"
        case .mentor: "师长"
        case .student: "学生"
        case .rival: "对手"
        case .enemy: "仇敌"
        case .other: "其他"
        }
    }

    /// 反过来怎么称呼，用于在对方详情里显示。
    public var reverse: RelationKind {
        switch self {
        case .father, .mother: .child
        case .child: .father
        case .grandparent: .child
        case .elderBrother: .youngerBrother
        case .youngerBrother: .elderBrother
        case .elderSister: .youngerSister
        case .youngerSister: .elderSister
        case .mentor: .student
        case .student: .mentor
        case .sibling, .spouse, .lover, .friend, .rival, .enemy, .other: self
        }
    }
}

public struct CharacterRelation: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var kind: RelationKind
    public var target: CharacterID

    public init(id: UUID = UUID(), kind: RelationKind, target: CharacterID) {
        self.id = id
        self.kind = kind
        self.target = target
    }
}

public struct StoryCharacter: Codable, Sendable, Identifiable, Hashable {
    public var id: CharacterID
    public var name: String
    public var summary: String
    public var notes: String
    /// 这个人物与其它人物的亲属/亲友关系。只存有向的一份。
    public var relations: [CharacterRelation]

    public init(
        id: CharacterID = CharacterID(),
        name: String,
        summary: String = "",
        notes: String = "",
        relations: [CharacterRelation] = []
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.notes = notes
        self.relations = relations
    }

    /// 旧工程包里没有 relations，缺了按空处理。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CharacterID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        relations = try container.decodeIfPresent([CharacterRelation].self, forKey: .relations) ?? []
    }
}

public struct StoryPlace: Codable, Sendable, Identifiable, Hashable {
    public var id: PlaceID
    public var name: String
    public var summary: String
    public var notes: String

    public init(id: PlaceID = PlaceID(), name: String, summary: String = "", notes: String = "") {
        self.id = id
        self.name = name
        self.summary = summary
        self.notes = notes
    }
}

// MARK: - 设定

/// 设定条目。确认状态与锁定状态分开：只有作者能确认或解锁，AI 只能建议。
public struct Setting: Codable, Sendable, Identifiable, Hashable {
    public var id: SettingID
    public var title: String
    public var text: String
    public var isConfirmed: Bool
    public var isLocked: Bool
    /// 挂载节点。删除节点不得连带删除设定。
    public var attachedNodeIDs: [NodeID]
    public var createdAt: Date
    public var modifiedAt: Date
    public var revision: Int

    public init(
        id: SettingID = SettingID(),
        title: String,
        text: String = "",
        isConfirmed: Bool = false,
        isLocked: Bool = false,
        attachedNodeIDs: [NodeID] = [],
        createdAt: Date = Timestamp.now(),
        modifiedAt: Date = Timestamp.now(),
        revision: Int = 0
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.isConfirmed = isConfirmed
        self.isLocked = isLocked
        self.attachedNodeIDs = attachedNodeIDs
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.revision = revision
        self.normalize()
    }

    /// 锁定的设定必须同时是已确认的。
    public mutating func normalize() {
        if isLocked { isConfirmed = true }
    }

    /// 供 AI 上下文使用的判定：本轮相关且已确认（含锁定）。
    public var isUsableAsEstablishedFact: Bool { isConfirmed }

    /// AI 不得改动的判定。
    public var isImmutableByAI: Bool { isLocked }
}

// MARK: - 图片资源

public struct Asset: Codable, Sendable, Identifiable, Hashable {
    public var id: AssetID
    /// 包内相对路径：assets/<fileName>
    public var fileName: String
    public var sha256: String?
    /// 用于快速判断磁盘文件是否已是最新，避免每次保存重写大图。
    public var byteCount: Int?
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// 配图说明。AI 默认只发送说明文字。
    public var caption: String
    public var createdAt: Date

    public init(
        id: AssetID = AssetID(),
        fileName: String,
        sha256: String? = nil,
        byteCount: Int? = nil,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        caption: String = "",
        createdAt: Date = Timestamp.now()
    ) {
        self.id = id
        self.fileName = fileName
        self.sha256 = sha256
        self.byteCount = byteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.caption = caption
        self.createdAt = createdAt
    }
}

// MARK: - 讨论

public enum MessageRole: String, Codable, Sendable, Hashable {
    case author
    case assistant
    case system
}

public struct Message: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var role: MessageRole
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), role: MessageRole, text: String, createdAt: Date = Timestamp.now()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

/// 讨论引用的材料。输入区按它显示“本轮引用了哪些材料”。
public enum DiscussionReference: Codable, Sendable, Hashable {
    case node(NodeID)
    case chapter(ChapterID)
    case setting(SettingID)
    case character(CharacterID)
    case place(PlaceID)
}

public struct Discussion: Codable, Sendable, Identifiable, Hashable {
    public var id: DiscussionID
    public var title: String
    public var anchorNodeID: NodeID?
    public var references: [DiscussionReference]
    public var messages: [Message]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: DiscussionID = DiscussionID(),
        title: String = CoreText.text("新讨论"),
        anchorNodeID: NodeID? = nil,
        references: [DiscussionReference] = [],
        messages: [Message] = [],
        createdAt: Date = Timestamp.now(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.anchorNodeID = anchorNodeID
        self.references = references
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
