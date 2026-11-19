import Foundation

/// 导出契约：按 schemaVersion 校验一份工程 JSON 的必填字段集合。
///
/// 只要求非可选字段。v2a 的六个场景字段、`coverAssetID`、`workingRouteEndingID`
/// 这类可空字段允许缺席，导出方与消费方都按“有就读、没有就按默认”处理。
public enum ProjectContract {
    /// 返回缺失字段的路径；空数组表示通过。路径带下标，例如 `nodes[2].body`。
    public static func missingFields(in data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            return ["<root>"]
        }
        var missing: [String] = []
        let version = root["schemaVersion"] as? Int ?? 1

        require(root, topLevel(version), at: "", into: &missing)

        checkArray(root, "chapters", fields: chapterFields, into: &missing)
        checkArray(root, "nodes", fields: nodeFields, into: &missing)
        checkArray(root, "edges", fields: edgeFields, into: &missing)
        checkArray(root, "characters", fields: characterFields, into: &missing)
        checkArray(root, "places", fields: placeFields, into: &missing)
        checkArray(root, "settings", fields: settingFields, into: &missing)
        checkArray(root, "assets", fields: assetFields, into: &missing)
        checkArray(root, "discussions", fields: discussionFields, into: &missing)

        checkNestedArrays(root, into: &missing)
        checkCanvas(root, key: "canvas", into: &missing)
        checkCanvas(root, key: "characterCanvas", into: &missing)
        return missing.sorted()
    }

    // MARK: 字段集合

    private static func topLevel(_ version: Int) -> Set<String> {
        var fields: Set<String> = [
            "schemaVersion", "id", "title", "logline", "createdAt", "modifiedAt", "revision",
            "chapters", "nodes", "edges", "characters", "places", "settings", "assets",
            "discussions", "canvas", "characterCanvas",
        ]
        if version >= 2 {
            fields.insert("cardGroupOverrides")
        }
        return fields
    }

    private static let nodeFields: Set<String> = [
        "id", "kind", "status", "title", "summary", "body", "isEntry",
        "characterIDs", "placeIDs", "settingIDs", "annotation",
        "createdAt", "modifiedAt", "revision",
    ]

    private static let chapterFields: Set<String> = [
        "id", "title", "summary", "order", "isCollapsedOnCanvas", "createdAt",
    ]

    private static let edgeFields: Set<String> = [
        "id", "from", "to", "kind", "label", "condition", "annotation", "isMainline",
    ]

    private static let characterFields: Set<String> = [
        "id", "name", "summary", "notes", "relations",
    ]

    private static let relationFields: Set<String> = ["id", "kind", "target"]
    private static let placeFields: Set<String> = ["id", "name", "summary", "notes"]
    private static let settingFields: Set<String> = [
        "id", "title", "text", "isConfirmed", "isLocked", "attachedNodeIDs",
        "createdAt", "modifiedAt", "revision",
    ]
    private static let assetFields: Set<String> = [
        "id", "fileName", "pixelWidth", "pixelHeight", "caption", "createdAt",
    ]
    private static let discussionFields: Set<String> = [
        "id", "title", "references", "messages", "createdAt", "updatedAt",
    ]
    private static let messageFields: Set<String> = ["id", "role", "text", "createdAt"]

    // MARK: 校验

    private static func require(
        _ object: [String: Any],
        _ fields: Set<String>,
        at path: String,
        into missing: inout [String]
    ) {
        for field in fields.sorted() where object[field] == nil {
            missing.append(path.isEmpty ? field : "\(path).\(field)")
        }
    }

    private static func checkArray(
        _ root: [String: Any],
        _ key: String,
        fields: Set<String>,
        into missing: inout [String]
    ) {
        guard let array = root[key] as? [[String: Any]] else { return }
        for (index, element) in array.enumerated() {
            require(element, fields, at: "\(key)[\(index)]", into: &missing)
        }
    }

    private static func checkNestedArrays(_ root: [String: Any], into missing: inout [String]) {
        if let characters = root["characters"] as? [[String: Any]] {
            for (index, character) in characters.enumerated() {
                guard let relations = character["relations"] as? [[String: Any]] else { continue }
                for (relationIndex, relation) in relations.enumerated() {
                    require(
                        relation,
                        relationFields,
                        at: "characters[\(index)].relations[\(relationIndex)]",
                        into: &missing
                    )
                }
            }
        }
        if let discussions = root["discussions"] as? [[String: Any]] {
            for (index, discussion) in discussions.enumerated() {
                guard let messages = discussion["messages"] as? [[String: Any]] else { continue }
                for (messageIndex, message) in messages.enumerated() {
                    require(
                        message,
                        messageFields,
                        at: "discussions[\(index)].messages[\(messageIndex)]",
                        into: &missing
                    )
                }
            }
        }
    }

    private static func checkCanvas(_ root: [String: Any], key: String, into missing: inout [String]) {
        guard let points = root[key] as? [String: Any] else { return }
        for (nodeID, value) in points {
            guard let point = value as? [String: Any] else {
                missing.append("\(key)[\(nodeID)]")
                continue
            }
            require(point, ["x", "y"], at: "\(key)[\(nodeID)]", into: &missing)
        }
    }
}
