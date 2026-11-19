import Foundation

/// 线索的类型。伏笔是唯一会自动进体检（N16 / N17）的一类，其余只做归类。
public enum ThreadKind: String, Codable, Sendable, CaseIterable, Hashable {
    case foreshadow
    case theme
    case arc
    case quest
    case reveal

    public var displayName: String {
        switch self {
        case .foreshadow: "伏笔"
        case .theme: "主题"
        case .arc: "人物弧线"
        case .quest: "任务"
        case .reveal: "真相"
        }
    }
}

/// 一个点在一条线索里的作用。
public enum ThreadRole: String, Codable, Sendable, CaseIterable, Hashable {
    case plant
    case reinforce
    case payoff
    case subvert

    public var displayName: String {
        switch self {
        case .plant: "埋"
        case .reinforce: "加深"
        case .payoff: "收"
        case .subvert: "反转"
        }
    }
}

/// 线索上的一个点：哪一场、做什么。
public struct ThreadEntry: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var nodeID: NodeID
    public var role: ThreadRole
    public var text: String

    public init(
        id: UUID = UUID(),
        nodeID: NodeID,
        role: ThreadRole = .plant,
        text: String = ""
    ) {
        self.id = id
        self.nodeID = nodeID
        self.role = role
        self.text = text
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        nodeID = try container.decode(NodeID.self, forKey: .nodeID)
        role = try container.decodeIfPresent(ThreadRole.self, forKey: .role) ?? .plant
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}

/// 一条跨场的线索。点内嵌在线上，按章序渲染成脊柱。
public struct StoryThread: Codable, Sendable, Identifiable, Hashable {
    public var id: ThreadID
    public var name: String
    public var kind: ThreadKind
    public var colorHex: String
    public var summary: String
    public var notes: String
    public var entries: [ThreadEntry]

    public init(
        id: ThreadID = ThreadID(),
        name: String,
        kind: ThreadKind = .foreshadow,
        colorHex: String = "",
        summary: String = "",
        notes: String = "",
        entries: [ThreadEntry] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.colorHex = colorHex
        self.summary = summary
        self.notes = notes
        self.entries = entries
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(ThreadID.self, forKey: .id) ?? ThreadID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名线索"
        kind = try container.decodeIfPresent(ThreadKind.self, forKey: .kind) ?? .foreshadow
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        entries = try container.decodeIfPresent([ThreadEntry].self, forKey: .entries) ?? []
    }

    public var hasPlant: Bool { entries.contains { $0.role == .plant } }
    public var hasPayoff: Bool { entries.contains { $0.role == .payoff || $0.role == .subvert } }
    public var isUnpaid: Bool { hasPlant && !hasPayoff }
}
