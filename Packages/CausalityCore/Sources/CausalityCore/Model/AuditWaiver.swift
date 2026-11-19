import Foundation

/// 一条「已忽略」记录。按规则 + 对象（节点 ID 或 `-`）匹配，理由留给下次看的人。
public struct AuditWaiver: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var ruleID: String
    public var subjectID: String
    public var reason: String
    public var createdAt: Date

    public var waiverKey: String { "\(ruleID):\(subjectID)" }

    public init(
        id: UUID = UUID(),
        ruleID: String,
        subjectID: String,
        reason: String = "",
        createdAt: Date = Timestamp.now()
    ) {
        self.id = id
        self.ruleID = ruleID
        self.subjectID = subjectID
        self.reason = reason
        self.createdAt = createdAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        ruleID = try container.decodeIfPresent(String.self, forKey: .ruleID) ?? ""
        subjectID = try container.decodeIfPresent(String.self, forKey: .subjectID) ?? "-"
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Timestamp.now()
    }
}
