import Foundation

// MARK: - 模型返回的提案内容

/// 只包含模型该产出的内容。ID、版本号、作者侧快照都由 App 记录，不向模型索取。
public struct ProposalPayload: Codable, Sendable, Equatable {
    public var summary: String
    public var nodes: [NodeDraft]
    public var edges: [EdgeDraft]
    public var changes: [ProposalChange]
    public var removals: [ProposalRemoval]
    public var notes: [String]

    public init(
        summary: String = "",
        nodes: [NodeDraft] = [],
        edges: [EdgeDraft] = [],
        changes: [ProposalChange] = [],
        removals: [ProposalRemoval] = [],
        notes: [String] = []
    ) {
        self.summary = summary
        self.nodes = nodes
        self.edges = edges
        self.changes = changes
        self.removals = removals
        self.notes = notes
    }

    public var isEmpty: Bool {
        nodes.isEmpty && edges.isEmpty && changes.isEmpty && removals.isEmpty
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = (try? container.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        nodes = (try? container.decodeIfPresent([NodeDraft].self, forKey: .nodes)) ?? []
        edges = (try? container.decodeIfPresent([EdgeDraft].self, forKey: .edges)) ?? []
        changes = (try? container.decodeIfPresent([ProposalChange].self, forKey: .changes)) ?? []
        removals = (try? container.decodeIfPresent([ProposalRemoval].self, forKey: .removals)) ?? []
        notes = (try? container.decodeIfPresent([String].self, forKey: .notes)) ?? []
    }
}

/// 新增节点。`afterRef` 可以是现有节点 UUID 字符串，也可以是本提案里的某个 `ref`。
///
/// 没有严格结构化输出的模型经常会漏 `ref`、把 `body` 写成 `text`，
/// 这里按常见写法宽松解码，真正的合法性由提案校验负责。
public struct NodeDraft: Codable, Sendable, Equatable {
    public var ref: String
    public var title: String
    public var kind: NodeKind
    public var summary: String
    public var body: String
    public var characterNames: [String]
    public var placeNames: [String]
    public var settingTitles: [String]
    public var afterRef: String?

    public init(
        ref: String,
        title: String,
        kind: NodeKind = .event,
        summary: String = "",
        body: String = "",
        characterNames: [String] = [],
        placeNames: [String] = [],
        settingTitles: [String] = [],
        afterRef: String? = nil
    ) {
        self.ref = ref
        self.title = title
        self.kind = kind
        self.summary = summary
        self.body = body
        self.characterNames = characterNames
        self.placeNames = placeNames
        self.settingTitles = settingTitles
        self.afterRef = afterRef
    }

    private enum ExtraKeys: String, CodingKey {
        case id
        case key
        case text
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let extra = try decoder.container(keyedBy: ExtraKeys.self)

        let rawRef = (try? container.decodeIfPresent(String.self, forKey: .ref))
            ?? (try? extra.decodeIfPresent(String.self, forKey: .id))
            ?? (try? extra.decodeIfPresent(String.self, forKey: .key))
        let title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        ref = (rawRef?.isEmpty == false ? rawRef! : "n_" + UUID().uuidString.prefix(6).lowercased())
        self.title = title.isEmpty ? "未命名场景" : title
        kind = Self.kind(from: (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? "")
        summary = (try? container.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        body = (try? container.decodeIfPresent(String.self, forKey: .body))
            ?? (try? extra.decodeIfPresent(String.self, forKey: .text))
            ?? ""
        characterNames = (try? container.decodeIfPresent([String].self, forKey: .characterNames)) ?? []
        placeNames = (try? container.decodeIfPresent([String].self, forKey: .placeNames)) ?? []
        settingTitles = (try? container.decodeIfPresent([String].self, forKey: .settingTitles)) ?? []
        afterRef = try? container.decodeIfPresent(String.self, forKey: .afterRef)
    }

    static func kind(from raw: String) -> NodeKind {
        NodeKind(rawValue: raw) ?? (raw.contains("choice") ? .choice : (raw.contains("end") ? .ending : .event))
    }

    static func edgeKind(from raw: String) -> EdgeKind {
        EdgeKind(rawValue: raw)
            ?? (raw.contains("cause") ? .cause
                : raw.contains("choice") ? .choice
                : raw.contains("condition") ? .condition
                : .plain)
    }
}

/// 新增发展线。`from`/`to` 同样接受 UUID 字符串或提案内 `ref`。
public struct EdgeDraft: Codable, Sendable, Equatable {
    public var from: String
    public var to: String
    public var kind: EdgeKind
    public var label: String
    public var condition: String

    public init(
        from: String,
        to: String,
        kind: EdgeKind = .plain,
        label: String = "",
        condition: String = ""
    ) {
        self.from = from
        self.to = to
        self.kind = kind
        self.label = label
        self.condition = condition
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = (try? container.decodeIfPresent(String.self, forKey: .from)) ?? ""
        to = (try? container.decodeIfPresent(String.self, forKey: .to)) ?? ""
        kind = NodeDraft.edgeKind(from: (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? "")
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? ""
        condition = (try? container.decodeIfPresent(String.self, forKey: .condition)) ?? ""
    }
}

public enum ProposalTarget: String, Codable, Sendable, CaseIterable {
    case node
    case edge
    case setting
}

/// 对现有实体的改动。字段为 nil 表示不动这一项。
public struct ProposalChange: Codable, Sendable, Equatable {
    public var target: ProposalTarget
    public var id: String
    public var title: String?
    public var summary: String?
    public var body: String?
    public var nodeKind: NodeKind?
    public var label: String?
    public var condition: String?
    public var edgeKind: EdgeKind?
    public var text: String?

    public init(
        target: ProposalTarget,
        id: String,
        title: String? = nil,
        summary: String? = nil,
        body: String? = nil,
        nodeKind: NodeKind? = nil,
        label: String? = nil,
        condition: String? = nil,
        edgeKind: EdgeKind? = nil,
        text: String? = nil
    ) {
        self.target = target
        self.id = id
        self.title = title
        self.summary = summary
        self.body = body
        self.nodeKind = nodeKind
        self.label = label
        self.condition = condition
        self.edgeKind = edgeKind
        self.text = text
    }

    private enum ExtraKeys: String, CodingKey {
        case field
        case after
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let extra = try decoder.container(keyedBy: ExtraKeys.self)
        let rawTarget = (try? container.decodeIfPresent(String.self, forKey: .target)) ?? "node"
        target = ProposalTarget(rawValue: rawTarget) ?? .node
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? ""
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        summary = try? container.decodeIfPresent(String.self, forKey: .summary)
        body = try? container.decodeIfPresent(String.self, forKey: .body)
        nodeKind = (try? container.decodeIfPresent(String.self, forKey: .nodeKind))
            .flatMap { $0.isEmpty ? nil : NodeDraft.kind(from: $0) }
        label = try? container.decodeIfPresent(String.self, forKey: .label)
        condition = try? container.decodeIfPresent(String.self, forKey: .condition)
        edgeKind = (try? container.decodeIfPresent(String.self, forKey: .edgeKind))
            .flatMap { $0.isEmpty ? nil : NodeDraft.edgeKind(from: $0) }
        text = try? container.decodeIfPresent(String.self, forKey: .text)

        // 有的模型用 {field: "body", before: "...", after: "..."} 描述改动，映射过来。
        if let fieldName = try? extra.decodeIfPresent(String.self, forKey: .field),
           let updated = try? extra.decodeIfPresent(String.self, forKey: .after) {
            apply(field: fieldName, value: updated)
        }
    }

    private mutating func apply(field: String, value: String) {
        switch field.lowercased() {
        case "body", "text", "正文": if body == nil { body = value }
        case "summary", "摘要": if summary == nil { summary = value }
        case "title", "标题": if title == nil { title = value }
        case "label", "选项", "文字": if label == nil { label = value }
        case "condition", "条件": if condition == nil { condition = value }
        default: break
        }
    }
}

public struct ProposalRemoval: Codable, Sendable, Equatable {
    public var target: ProposalTarget
    public var id: String

    public init(target: ProposalTarget, id: String) {
        self.target = target
        self.id = id
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawTarget = (try? container.decodeIfPresent(String.self, forKey: .target)) ?? "node"
        target = ProposalTarget(rawValue: rawTarget) ?? .node
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? ""
    }
}

// MARK: - App 侧包裹

/// 一份待审提案。作者看到的是它，采纳的也是它。
public struct AIProposal: Sendable, Equatable {
    public var id: UUID
    /// 发起请求时的项目版本。
    public var baseRevision: Int
    /// 发起请求时被引用节点的版本，用于发现“等待期间作者改过同一节点”。
    public var nodeRevisions: [NodeID: Int]
    public var payload: ProposalPayload

    public init(
        id: UUID = UUID(),
        baseRevision: Int,
        nodeRevisions: [NodeID: Int] = [:],
        payload: ProposalPayload
    ) {
        self.id = id
        self.baseRevision = baseRevision
        self.nodeRevisions = nodeRevisions
        self.payload = payload
    }
}

// MARK: - 结构化输出用的 JSON Schema

public enum ProposalSchema {
    public static let name = "causal_proposal"

    /// 严格模式要求：所有字段必填、additionalProperties 为 false、可选项用 null 联合。
    public static let json = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["summary", "nodes", "edges", "changes", "removals", "notes"],
      "properties": {
        "summary": {"type": "string"},
        "nodes": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["ref", "title", "kind", "summary", "body", "characterNames", "placeNames", "settingTitles", "afterRef"],
            "properties": {
              "ref": {"type": "string"},
              "title": {"type": "string"},
              "kind": {"type": "string", "enum": ["event", "choice", "ending"]},
              "summary": {"type": "string"},
              "body": {"type": "string"},
              "characterNames": {"type": "array", "items": {"type": "string"}},
              "placeNames": {"type": "array", "items": {"type": "string"}},
              "settingTitles": {"type": "array", "items": {"type": "string"}},
              "afterRef": {"type": ["string", "null"]}
            }
          }
        },
        "edges": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["from", "to", "kind", "label", "condition"],
            "properties": {
              "from": {"type": "string"},
              "to": {"type": "string"},
              "kind": {"type": "string", "enum": ["cause", "choice", "condition", "plain"]},
              "label": {"type": "string"},
              "condition": {"type": "string"}
            }
          }
        },
        "changes": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["target", "id", "title", "summary", "body", "nodeKind", "label", "condition", "edgeKind", "text"],
            "properties": {
              "target": {"type": "string", "enum": ["node", "edge", "setting"]},
              "id": {"type": "string"},
              "title": {"type": ["string", "null"]},
              "summary": {"type": ["string", "null"]},
              "body": {"type": ["string", "null"]},
              "nodeKind": {"type": ["string", "null"], "enum": ["event", "choice", "ending", null]},
              "label": {"type": ["string", "null"]},
              "condition": {"type": ["string", "null"]},
              "edgeKind": {"type": ["string", "null"], "enum": ["cause", "choice", "condition", "plain", null]},
              "text": {"type": ["string", "null"]}
            }
          }
        },
        "removals": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["target", "id"],
            "properties": {
              "target": {"type": "string", "enum": ["node", "edge", "setting"]},
              "id": {"type": "string"}
            }
          }
        },
        "notes": {"type": "array", "items": {"type": "string"}}
      }
    }
    """
}
