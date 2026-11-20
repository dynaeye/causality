import Foundation

/// 把「一、二、三幕 + 节点表格」形式的文字故事板读成工程。
///
/// 认三种内容：
/// - `## 标题` 下的 `| 节点与时机 | 眼前 | 动手 | 留下 |` 表 → 一章，一行一张卡；
/// - 其他表（如四向表）→ 灵感卡；
/// - 章节里的 `- **小标题**：正文` → 灵感卡。
///
/// 卡片之间的因果按表格行序串起来，连线文字取「留下什么」的首句。
public enum StoryboardMarkdown {
    public enum ImportError: Error, CustomStringConvertible, LocalizedError {
        case noContent

        public var description: String {
            switch self {
            case .noContent: CoreText.text("没有找到可导入的章节或表格")
            }
        }

        public var errorDescription: String? { description }
    }

    private struct Section {
        var title: String
        var header: [String]?
        var rows: [[String]] = []
        var bullets: [String] = []
    }

    private struct Parsed {
        var docTitle = ""
        var logline = ""
        var sections: [Section] = []
    }

    // MARK: - 入口

    /// 从文字故事板建工程。`title` 为空时用文内一级标题。
    public static func makeProject(
        fromMarkdown text: String,
        title fallbackTitle: String = "",
        seed: UInt64 = 7,
        localize: (String) -> String = { CoreText.localize($0) }
    ) throws -> StoryProject {
        let parsed = parse(text)
        let board = parsed.sections.filter { isBoardHeader($0.header, localize: localize) && !$0.rows.isEmpty }
        guard !board.isEmpty else { throw ImportError.noContent }

        var base = StoryProject.empty(title: fallbackTitle.isEmpty ? parsed.docTitle : fallbackTitle)
        base.logline = String(parsed.logline.prefix(400))
        var builder = ProjectBuilder(project: base, seed: seed)
        let library = MarkdownLibrary.parse(text: text, builder: &builder)

        let chain = addBoard(board, to: &builder, library: library, localize: localize)
        connect(chain, in: &builder)
        // 卡片按阅读顺序排成蛇形，相邻两张的连线最短。
        builder.apply(CanvasLayout.arrange(project: builder.project))
        addReference(
            from: parsed.sections,
            to: &builder,
            skipping: library.sectionTitles,
            localize: localize
        )
        return builder.finalized()
    }

    // MARK: - 解析

    private static func parse(_ text: String) -> Parsed {
        var parsed = Parsed()
        var awaitingHeader = false

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("## ") {
                parsed.sections.append(Section(title: plain(String(line.dropFirst(3)))))
                awaitingHeader = true
            } else if line.hasPrefix("# ") {
                parsed.docTitle = plain(String(line.dropFirst(2)))
            } else if line.hasPrefix("|") {
                guard var section = parsed.sections.last else { continue }
                parsed.sections.removeLast()
                let cells = splitRow(line)
                if cells.allSatisfy(isRule) || cells.allSatisfy(\.isEmpty) {
                    parsed.sections.append(section)
                    continue
                }
                if awaitingHeader || section.header == nil {
                    section.header = cells
                    awaitingHeader = false
                } else {
                    section.rows.append(cells)
                }
                parsed.sections.append(section)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                guard var section = parsed.sections.last else { continue }
                parsed.sections.removeLast()
                section.bullets.append(String(line.dropFirst(2)))
                parsed.sections.append(section)
            } else if parsed.sections.isEmpty, parsed.logline.isEmpty, line.hasPrefix("**") {
                parsed.logline = plain(line)
            }
        }
        return parsed
    }

    // MARK: - 章与卡

    private struct Link {
        var node: NodeID
        var lead: String
    }

    private static func addBoard(
        _ sections: [Section],
        to builder: inout ProjectBuilder,
        library: MarkdownLibrary,
        localize: (String) -> String
    ) -> [Link] {
        var chain: [Link] = []
        for section in sections {
            _ = builder.addChapter(title: section.title)
            guard let chapterID = builder.project.chapters.last?.id else { continue }
            for row in section.rows {
                let cells = padded(row, count: 4)
                let heading = splitTiming(cells[0])
                let text = cells.dropFirst().joined(separator: " ")

                let nodeID = builder.addNode(
                    title: heading.title,
                    summary: cells[1],
                    body: cardBody(cells, localize: localize),
                    chapterID: chapterID,
                    isEntry: chain.isEmpty,
                    characters: library.characters.filter { text.contains($0.name) }.map(\.id),
                    places: library.places.filter { text.contains($0.name) }.map(\.id),
                    settings: [],
                    position: nil
                )
                for setting in library.settings where text.contains(setting.title) {
                    builder.attach(setting.id, to: nodeID)
                }
                if !heading.timing.isEmpty {
                    builder.apply(ProjectMutations.updateNode(nodeID, in: builder.project) { node in
                        node.annotation = heading.timing
                    })
                }
                chain.append(Link(node: nodeID, lead: firstSentence(cells[3])))
            }
        }
        return chain
    }

    private static func connect(_ chain: [Link], in builder: inout ProjectBuilder) {
        for (from, to) in zip(chain, chain.dropFirst()) {
            builder.connect(from.node, to: to.node, label: String(from.lead.prefix(28)))
        }
    }

    // MARK: - 参考材料

    private static func addReference(
        from sections: [Section],
        to builder: inout ProjectBuilder,
        skipping libraryTitles: Set<String>,
        localize: (String) -> String
    ) {
        for section in sections where !isBoardHeader(section.header, localize: localize)
            && !libraryTitles.contains(section.title) {
            if let header = section.header, !section.rows.isEmpty {
                for row in section.rows {
                    let pairs = zip(header.dropFirst(), row.dropFirst())
                        .filter { !$0.1.isEmpty }
                        .map { "\($0.0)：\($0.1)" }
                    _ = builder.addNode(
                        title: row.first ?? "未命名",
                        summary: pairs.first ?? "",
                        body: pairs.joined(separator: "\n"),
                        status: .idea
                    )
                }
            }
            for bullet in section.bullets {
                let parts = splitLead(bullet)
                _ = builder.addNode(
                    title: parts.head.isEmpty ? section.title : parts.head,
                    summary: String(parts.tail.prefix(60)),
                    body: parts.tail,
                    status: .idea
                )
            }
        }
    }

    // MARK: - 文本处理

    private static func splitRow(_ line: String) -> [String] {
        var body = line
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        return body.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isRule(_ cell: String) -> Bool {
        !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" }
    }

    private static func padded(_ cells: [String], count: Int) -> [String] {
        cells + Array(repeating: "", count: max(0, count - cells.count))
    }

    /// 「S01 入镇，当日下午」→ 标题「S01 入镇」，时机「当日下午」。
    private static func splitTiming(_ cell: String) -> (title: String, timing: String) {
        if let comma = cell.firstIndex(where: { $0 == "，" || $0 == "," }) {
            let head = String(cell[cell.startIndex..<comma]).trimmingCharacters(in: .whitespaces)
            let tail = String(cell[cell.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
            return (head, tail)
        }
        return (cell, "")
    }

    private static func cardBody(_ cells: [String], localize: (String) -> String) -> String {
        var lines: [String] = []
        if !cells[1].isEmpty { lines.append(String(format: localize("眼前：%@"), cells[1])) }
        if !cells[2].isEmpty { lines.append(String(format: localize("动手：%@"), cells[2])) }
        if !cells[3].isEmpty { lines.append(String(format: localize("留下：%@"), cells[3])) }
        return lines.joined(separator: "\n\n")
    }

    // MARK: - 表头

    private static func boardHeaderNames(localize: (String) -> String) -> Set<String> {
        ["节点与时机", localize("节点与时机")]
    }

    /// 中文表头与当前界面语言的表头都认。
    static func isBoardHeader(
        _ cells: [String]?,
        localize: (String) -> String = { CoreText.localize($0) }
    ) -> Bool {
        guard let first = cells?.first?.trimmingCharacters(in: .whitespaces) else { return false }
        return boardHeaderNames(localize: localize).contains(first)
    }

    static func isBoardHeader(
        line: String,
        localize: (String) -> String = { CoreText.localize($0) }
    ) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return false }
        var body = trimmed.dropFirst()
        if let end = body.firstIndex(of: "|") { body = body[..<end] }
        return boardHeaderNames(localize: localize).contains(body.trimmingCharacters(in: .whitespaces))
    }

    /// 「留下什么」的首句，用作连线上的因果文字。
    private static func firstSentence(_ text: String) -> String {
        let sentence = text.split(separator: "。").first.map(String.init) ?? text
        return sentence.trimmingCharacters(in: .whitespaces)
    }

    /// 「**人物因果**：正文」→ («人物因果», «正文»)
    private static func splitLead(_ bullet: String) -> (head: String, tail: String) {
        let stripped = bullet.replacingOccurrences(of: "**", with: "")
        guard let colon = stripped.firstIndex(where: { $0 == "：" || $0 == ":" }), bullet.contains("**") else {
            return ("", plain(stripped))
        }
        let head = String(stripped[stripped.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        let tail = String(stripped[stripped.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (head, tail)
    }

    /// 去掉 markdown 记号。
    private static func plain(_ text: String) -> String {
        var value = text
        for token in ["**", "__", "`"] {
            value = value.replacingOccurrences(of: token, with: "")
        }
        return value.trimmingCharacters(in: .whitespaces)
    }
}
