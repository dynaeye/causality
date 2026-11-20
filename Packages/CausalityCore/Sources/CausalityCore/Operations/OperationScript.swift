import Foundation

/// 一批编辑操作的文字形式：给命令行、MCP 与以后的自动化用的稳定接口。
///
/// 一份脚本长这样：
///
/// ```json
/// {
///   "version": 1,
///   "ops": [
///     { "op": "addCard", "chapter": "第三幕 · 从东渡出发", "title": "S10 尾声", "body": "…", "after": "S09 归家" },
///     { "op": "connect", "from": "S09 归家", "to": "S10 尾声", "label": "带回来的方子" }
///   ]
/// }
/// ```
///
/// 引用卡片、章节、人物、地点、设定时，写名字或写 UUID 都行；重名会报错并列出候选。
public struct OperationScript: Decodable, Sendable, Equatable {
    public var version: Int
    public var ops: [ScriptOp]

    private enum CodingKeys: String, CodingKey {
        case version, ops
    }

    public init(version: Int = 1, ops: [ScriptOp]) {
        self.version = version
        self.ops = ops
    }

    /// 版本号可以省，缺一条 `ops` 才报错。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        ops = try container.decode([ScriptOp].self, forKey: .ops)
    }
}

/// 单条操作。命名与 `ProjectMutations` 一一对应，只把 ID 换成了可读的名字。
public enum ScriptOp: Sendable, Equatable {
    case updateHeader(title: String?, logline: String?)
    case arrangeCanvas(columns: Int?)

    case addChapter(title: String, summary: String?)
    case updateChapter(chapter: String, title: String?, summary: String?)
    case deleteChapter(chapter: String)

    case addCard(CardDraft)
    case updateCard(card: String, patch: CardPatch)
    case moveCard(card: String, chapter: String?, index: Int?)
    case deleteCard(card: String)
    case setEntry(card: String, isEntry: Bool)

    case connect(from: String, to: String, kind: EdgeKind?, label: String?, condition: String?, mainline: Bool?)
    case updateEdge(edge: String, label: String?, condition: String?, kind: EdgeKind?, mainline: Bool?)
    case deleteEdge(edge: String)

    case addCharacter(name: String, summary: String?, notes: String?)
    case updateCharacter(character: String, name: String?, summary: String?, notes: String?)
    case deleteCharacter(character: String)
    case addRelation(from: String, to: String, kind: RelationKind)

    case addPlace(name: String, summary: String?, notes: String?)
    case updatePlace(place: String, name: String?, summary: String?, notes: String?)

    case addSetting(title: String, text: String?, confirmed: Bool?, locked: Bool?)
    case updateSetting(setting: String, title: String?, text: String?, confirmed: Bool?, locked: Bool?)
    case attachSetting(setting: String, card: String)
    case detachSetting(setting: String, card: String)
    case deleteSetting(setting: String)
}

public struct CardDraft: Sendable, Equatable {
    public var chapter: String?
    public var title: String
    public var summary: String
    public var body: String
    public var kind: NodeKind
    public var status: NodeStatus
    public var isEntry: Bool
    public var after: String?
    public var index: Int?
    public var characters: [String]
    public var places: [String]
    public var settings: [String]

    public init(
        chapter: String? = nil,
        title: String,
        summary: String = "",
        body: String = "",
        kind: NodeKind = .event,
        status: NodeStatus = .draft,
        isEntry: Bool = false,
        after: String? = nil,
        index: Int? = nil,
        characters: [String] = [],
        places: [String] = [],
        settings: [String] = []
    ) {
        self.chapter = chapter
        self.title = title
        self.summary = summary
        self.body = body
        self.kind = kind
        self.status = status
        self.isEntry = isEntry
        self.after = after
        self.index = index
        self.characters = characters
        self.places = places
        self.settings = settings
    }
}

/// 改卡只说改哪几项，没写的保持原样。
public struct CardPatch: Sendable, Equatable {
    public var title: String?
    public var summary: String?
    public var body: String?
    public var kind: NodeKind?
    public var status: NodeStatus?
    public var isEntry: Bool?
    public var chapter: String?
    public var characters: [String]?
    public var places: [String]?
    public var annotation: String?

    public init(
        title: String? = nil,
        summary: String? = nil,
        body: String? = nil,
        kind: NodeKind? = nil,
        status: NodeStatus? = nil,
        isEntry: Bool? = nil,
        chapter: String? = nil,
        characters: [String]? = nil,
        places: [String]? = nil,
        annotation: String? = nil
    ) {
        self.title = title
        self.summary = summary
        self.body = body
        self.kind = kind
        self.status = status
        self.isEntry = isEntry
        self.chapter = chapter
        self.characters = characters
        self.places = places
        self.annotation = annotation
    }

    var isEmpty: Bool {
        title == nil && summary == nil && body == nil && kind == nil && status == nil
            && isEntry == nil && chapter == nil && characters == nil && places == nil
            && annotation == nil
    }
}

// MARK: - 解码

extension ScriptOp: Decodable {
    private enum CodingKeys: String, CodingKey {
        case op
        case title, logline, summary, text, notes, name, body
        case chapter, card, after, index, isEntry, kind, status, condition, label, mainline, columns
        case from, to, edge, character, place, setting, confirmed, locked
        case characters, places, settings, annotation
    }

    /// 读字段的小工具，省掉每处 try? / ?? 的噪音。
    private struct Reader {
        let tag: String
        let container: KeyedDecodingContainer<CodingKeys>

        func text(_ key: CodingKeys) -> String? {
            try? container.decodeIfPresent(String.self, forKey: key)
        }

        func int(_ key: CodingKeys) -> Int? {
            try? container.decodeIfPresent(Int.self, forKey: key)
        }

        func bool(_ key: CodingKeys) -> Bool? {
            try? container.decodeIfPresent(Bool.self, forKey: key)
        }

        func strings(_ key: CodingKeys) -> [String]? {
            try? container.decodeIfPresent([String].self, forKey: key)
        }

        func require(_ key: CodingKeys) throws -> String {
            guard let value = text(key), !value.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: key, in: container, debugDescription: CoreText.format("%@ 缺少 %@", tag, key.rawValue)
                )
            }
            return value
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(String.self, forKey: .op)
        let reader = Reader(tag: tag, container: container)

        if let op = try Self.decodeBoard(tag, reader) { self = op; return }
        if let op = try Self.decodeCards(tag, reader) { self = op; return }
        if let op = try Self.decodeEdges(tag, reader) { self = op; return }
        if let op = try Self.decodeEntities(tag, reader) { self = op; return }
        if let op = try Self.decodeSettings(tag, reader) { self = op; return }
        throw DecodingError.dataCorruptedError(
            forKey: .op, in: container, debugDescription: CoreText.format("不认识的 op：%@", tag)
        )
    }

    private static func decodeBoard(_ tag: String, _ reader: Reader) throws -> ScriptOp? {
        switch tag {
        case "updateHeader":
            return .updateHeader(title: reader.text(.title), logline: reader.text(.logline))
        case "arrangeCanvas":
            return .arrangeCanvas(columns: reader.int(.columns))
        case "addChapter":
            return .addChapter(title: try reader.require(.title), summary: reader.text(.summary))
        case "updateChapter":
            return .updateChapter(chapter: try reader.require(.chapter), title: reader.text(.title), summary: reader.text(.summary))
        case "deleteChapter":
            return .deleteChapter(chapter: try reader.require(.chapter))
        default:
            return nil
        }
    }

    private static func decodeCards(_ tag: String, _ reader: Reader) throws -> ScriptOp? {
        switch tag {
        case "addCard":
            return .addCard(CardDraft(
                chapter: reader.text(.chapter),
                title: try reader.require(.title),
                summary: reader.text(.summary) ?? "",
                body: reader.text(.body) ?? "",
                kind: (reader.text(.kind).flatMap(NodeKind.init(rawValue:))) ?? .event,
                status: (reader.text(.status).flatMap(NodeStatus.init(rawValue:))) ?? .draft,
                isEntry: reader.bool(.isEntry) ?? false,
                after: reader.text(.after),
                index: reader.int(.index),
                characters: reader.strings(.characters) ?? [],
                places: reader.strings(.places) ?? [],
                settings: reader.strings(.settings) ?? []
            ))
        case "updateCard":
            return .updateCard(card: try reader.require(.card), patch: CardPatch(
                title: reader.text(.title),
                summary: reader.text(.summary),
                body: reader.text(.body),
                kind: reader.text(.kind).flatMap(NodeKind.init(rawValue:)),
                status: reader.text(.status).flatMap(NodeStatus.init(rawValue:)),
                isEntry: reader.bool(.isEntry),
                chapter: reader.text(.chapter),
                characters: reader.strings(.characters),
                places: reader.strings(.places),
                annotation: reader.text(.annotation)
            ))
        case "moveCard":
            return .moveCard(card: try reader.require(.card), chapter: reader.text(.chapter), index: reader.int(.index))
        case "deleteCard":
            return .deleteCard(card: try reader.require(.card))
        case "setEntry":
            return .setEntry(card: try reader.require(.card), isEntry: try reader.container.decode(Bool.self, forKey: .isEntry))
        default:
            return nil
        }
    }

    private static func decodeEdges(_ tag: String, _ reader: Reader) throws -> ScriptOp? {
        switch tag {
        case "connect":
            return .connect(
                from: try reader.require(.from),
                to: try reader.require(.to),
                kind: reader.text(.kind).flatMap(EdgeKind.init(rawValue:)),
                label: reader.text(.label),
                condition: reader.text(.condition),
                mainline: reader.bool(.mainline)
            )
        case "updateEdge":
            return .updateEdge(
                edge: try reader.require(.edge),
                label: reader.text(.label),
                condition: reader.text(.condition),
                kind: reader.text(.kind).flatMap(EdgeKind.init(rawValue:)),
                mainline: reader.bool(.mainline)
            )
        case "deleteEdge":
            return .deleteEdge(edge: try reader.require(.edge))
        default:
            return nil
        }
    }

    private static func decodeEntities(_ tag: String, _ reader: Reader) throws -> ScriptOp? {
        switch tag {
        case "addCharacter":
            return .addCharacter(name: try reader.require(.name), summary: reader.text(.summary), notes: reader.text(.notes))
        case "updateCharacter":
            return .updateCharacter(
                character: try reader.require(.character),
                name: reader.text(.name),
                summary: reader.text(.summary),
                notes: reader.text(.notes)
            )
        case "deleteCharacter":
            return .deleteCharacter(character: try reader.require(.character))
        case "addRelation":
            guard let kind = reader.text(.kind).flatMap(RelationKind.init(rawValue:)) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .kind, in: reader.container, debugDescription: CoreText.text("addRelation 需要 kind")
                )
            }
            return .addRelation(from: try reader.require(.from), to: try reader.require(.to), kind: kind)
        case "addPlace":
            return .addPlace(name: try reader.require(.name), summary: reader.text(.summary), notes: reader.text(.notes))
        case "updatePlace":
            return .updatePlace(place: try reader.require(.place), name: reader.text(.name), summary: reader.text(.summary), notes: reader.text(.notes))
        default:
            return nil
        }
    }

    private static func decodeSettings(_ tag: String, _ reader: Reader) throws -> ScriptOp? {
        switch tag {
        case "addSetting":
            return .addSetting(
                title: try reader.require(.title),
                text: reader.text(.text),
                confirmed: reader.bool(.confirmed),
                locked: reader.bool(.locked)
            )
        case "updateSetting":
            return .updateSetting(
                setting: try reader.require(.setting),
                title: reader.text(.title),
                text: reader.text(.text),
                confirmed: reader.bool(.confirmed),
                locked: reader.bool(.locked)
            )
        case "attachSetting":
            return .attachSetting(setting: try reader.require(.setting), card: try reader.require(.card))
        case "detachSetting":
            return .detachSetting(setting: try reader.require(.setting), card: try reader.require(.card))
        case "deleteSetting":
            return .deleteSetting(setting: try reader.require(.setting))
        default:
            return nil
        }
    }

    public var name: String {
        switch self {
        case .updateHeader: "updateHeader"
        case .arrangeCanvas: "arrangeCanvas"
        case .addChapter: "addChapter"
        case .updateChapter: "updateChapter"
        case .deleteChapter: "deleteChapter"
        case .addCard: "addCard"
        case .updateCard: "updateCard"
        case .moveCard: "moveCard"
        case .deleteCard: "deleteCard"
        case .setEntry: "setEntry"
        case .connect: "connect"
        case .updateEdge: "updateEdge"
        case .deleteEdge: "deleteEdge"
        case .addCharacter: "addCharacter"
        case .updateCharacter: "updateCharacter"
        case .deleteCharacter: "deleteCharacter"
        case .addRelation: "addRelation"
        case .addPlace: "addPlace"
        case .updatePlace: "updatePlace"
        case .addSetting: "addSetting"
        case .updateSetting: "updateSetting"
        case .attachSetting: "attachSetting"
        case .detachSetting: "detachSetting"
        case .deleteSetting: "deleteSetting"
        }
    }
}
