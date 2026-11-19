import Foundation

/// 让 `ID` 可以作为 JSON 对象的键（画布坐标表按节点 ID 存储）。
struct StringCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}

/// 带类型标签的稳定 UUID。所有实体的身份都是 UUID，标签只用于编译期区分。
public struct ID<Tag: Hashable & Sendable>: Hashable, Sendable, CustomStringConvertible {
    public var rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init?(string: String) {
        guard let uuid = UUID(uuidString: string) else { return nil }
        self.rawValue = uuid
    }

    /// 固定 UUID，供 fixture 和测试使用。
    public static func fixed(_ value: String) -> ID<Tag>? {
        guard let uuid = UUID(uuidString: value) else { return nil }
        return ID(rawValue: uuid)
    }

    public var description: String { rawValue.uuidString }
}

extension ID: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(UUID.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ID: CodingKeyRepresentable {
    public var codingKey: any CodingKey { StringCodingKey(stringValue: rawValue.uuidString) }

    public init?<T>(codingKey: T) where T: CodingKey {
        guard let uuid = UUID(uuidString: codingKey.stringValue) else { return nil }
        self.init(rawValue: uuid)
    }
}

public enum NodeTag: Hashable, Sendable {}
public enum EdgeTag: Hashable, Sendable {}
public enum ChapterTag: Hashable, Sendable {}
public enum CharacterTag: Hashable, Sendable {}
public enum PlaceTag: Hashable, Sendable {}
public enum SettingTag: Hashable, Sendable {}
public enum AssetTag: Hashable, Sendable {}
public enum DiscussionTag: Hashable, Sendable {}
public enum ThreadTag: Hashable, Sendable {}

public typealias NodeID = ID<NodeTag>
public typealias EdgeID = ID<EdgeTag>
public typealias ChapterID = ID<ChapterTag>
public typealias CharacterID = ID<CharacterTag>
public typealias PlaceID = ID<PlaceTag>
public typealias SettingID = ID<SettingTag>
public typealias AssetID = ID<AssetTag>
public typealias DiscussionID = ID<DiscussionTag>
public typealias ThreadID = ID<ThreadTag>
