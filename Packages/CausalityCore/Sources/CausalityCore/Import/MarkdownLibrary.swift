import Foundation

/// 文字导入里的人物、地点、设定。
///
/// 只认文内显式写出的 `## 人物` / `## 地点` / `## 设定` 表或条目；
/// 没有就不建，不再往每个工程里塞一份示例库。
struct MarkdownLibrary {
    struct CharacterRef {
        var name: String
        var id: CharacterID
    }

    struct PlaceRef {
        var name: String
        var id: PlaceID
    }

    struct SettingRef {
        var title: String
        var id: SettingID
    }

    var characters: [CharacterRef] = []
    var places: [PlaceRef] = []
    var settings: [SettingRef] = []
    /// 被当作资料段的标题：这些段不再生成灵感卡。
    var sectionTitles: Set<String> = []

    static func parse(text: String, builder: inout ProjectBuilder) -> MarkdownLibrary {
        var library = MarkdownLibrary()
        var kind: Kind?
        var tableStarted = false

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                let title = plain(String(line.dropFirst(3)))
                kind = Kind(title: title)
                if kind != nil {
                    library.sectionTitles.insert(title)
                }
                tableStarted = false
                continue
            }
            if line.hasPrefix("# ") {
                kind = nil
                continue
            }
            guard let kind else { continue }

            if line.hasPrefix("|") {
                let cells = splitRow(line)
                if cells.allSatisfy(isRule) || cells.allSatisfy(\.isEmpty) { continue }
                if !tableStarted {
                    tableStarted = true
                    continue
                }
                library.add(cells, kind: kind, builder: &builder)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let parts = splitLead(String(line.dropFirst(2)))
                library.add([parts.head, parts.tail], kind: kind, builder: &builder)
            }
        }
        return library
    }

    /// 这个 `##` 标题是不是资料段。导出/渲染用同一套判断，避免两边打架。
    static func isLibraryTitle(_ title: String) -> Bool {
        Kind(title: title) != nil
    }

    private enum Kind {
        case character
        case place
        case setting

        init?(title: String) {
            let excluded = ["因果", "脉络", "关系", "矩阵", "弧线", "灵感", "备注", "参考"]
            guard !excluded.contains(where: title.contains) else { return nil }
            if Self.matches(title, "人物", "角色") {
                self = .character
            } else if Self.matches(title, "地点", "场所") {
                self = .place
            } else if Self.matches(title, "设定", "事实", "世界观") {
                self = .setting
            } else {
                return nil
            }
        }

        /// 中文标题与当前语言的词条都认；CLI 的 `--lang` 同样走这张表。
        private static func matches(_ title: String, _ keys: String...) -> Bool {
            keys.contains { key in
                title.contains(key) || title.contains(CoreText.localize(key))
            }
        }
    }

    private mutating func add(_ cells: [String], kind: Kind, builder: inout ProjectBuilder) {
        let name = Self.plain(cells.first ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let text = cells.dropFirst()
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        switch kind {
        case .character:
            characters.append(CharacterRef(name: name, id: builder.addCharacter(name: name, summary: text)))
        case .place:
            places.append(PlaceRef(name: name, id: builder.addPlace(name: name, summary: text)))
        case .setting:
            settings.append(SettingRef(title: name, id: builder.addSetting(title: name, text: text)))
        }
    }

    // MARK: 小工具

    private static func splitRow(_ line: String) -> [String] {
        var body = line
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        return body.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isRule(_ cell: String) -> Bool {
        !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" }
    }

    /// 「**林远**：收信人」→ («林远», «收信人»)
    private static func splitLead(_ bullet: String) -> (head: String, tail: String) {
        let stripped = bullet.replacingOccurrences(of: "**", with: "")
        guard let colon = stripped.firstIndex(where: { $0 == "：" || $0 == ":" }) else {
            return (plain(stripped), "")
        }
        let head = String(stripped[stripped.startIndex..<colon])
        let tail = String(stripped[stripped.index(after: colon)...])
        return (
            plain(head).trimmingCharacters(in: .whitespaces),
            plain(tail).trimmingCharacters(in: .whitespaces)
        )
    }

    private static func plain(_ text: String) -> String {
        var value = text
        for token in ["**", "__", "`"] {
            value = value.replacingOccurrences(of: token, with: "")
        }
        return value.trimmingCharacters(in: .whitespaces)
    }
}
