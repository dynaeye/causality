import Foundation

/// 人物在某一章里的状态。
public enum MatrixPresence: String, Sendable, CaseIterable {
    case present
    case mentioned
    case absent
    case unwritten

    public var displayName: String {
        switch self {
        case .present: "在场"
        case .mentioned: "只被提及"
        case .absent: "缺席"
        case .unwritten: "尚未写"
        }
    }
}

public struct CharacterMatrixRow: Identifiable, Sendable {
    public var character: StoryCharacter
    public var cells: [MatrixPresence]
    public var firstChapterIndex: Int?
    public var lastChapterIndex: Int?
    /// 两次在场之间连续缺席的章数最大值。
    public var longestGap: Int

    public var id: CharacterID { character.id }
}

/// 人物 × 章节。按首次出场排序，行尾带首末出场与最长空档。
public struct CharacterMatrix: Sendable {
    public var chapters: [Chapter]
    public var chapterWordCounts: [Int]
    public var rows: [CharacterMatrixRow]
}

public enum CharacterMatrixBuilder {
    public static func build(project: StoryProject) -> CharacterMatrix {
        let wordBook = WordCount.Book(project: project)
        let chapters = project.chapters
        let drafts = project.nodes.filter { $0.status == .draft }

        var nodesByChapter: [ChapterID: [StoryNode]] = [:]
        for node in drafts {
            if let chapterID = node.chapterID {
                nodesByChapter[chapterID, default: []].append(node)
            }
        }

        var rows: [CharacterMatrixRow] = []
        for character in project.characters {
            var cells: [MatrixPresence] = []
            var presentChapters: [Int] = []
            for (chapterIndex, chapter) in chapters.enumerated() {
                let nodes = nodesByChapter[chapter.id] ?? []
                if nodes.isEmpty {
                    cells.append(.unwritten)
                    continue
                }
                if nodes.contains(where: { $0.characterIDs.contains(character.id) }) {
                    cells.append(.present)
                    presentChapters.append(chapterIndex)
                    continue
                }
                let name = character.name
                let mentioned = !name.isEmpty && nodes.contains { node in
                    node.title.localizedCaseInsensitiveContains(name)
                        || node.summary.localizedCaseInsensitiveContains(name)
                        || node.body.localizedCaseInsensitiveContains(name)
                        || node.annotation.localizedCaseInsensitiveContains(name)
                }
                cells.append(mentioned ? .mentioned : .absent)
            }

            var longestGap = 0
            for (before, after) in zip(presentChapters, presentChapters.dropFirst()) {
                longestGap = max(longestGap, after - before - 1)
            }
            rows.append(
                CharacterMatrixRow(
                    character: character,
                    cells: cells,
                    firstChapterIndex: presentChapters.first,
                    lastChapterIndex: presentChapters.last,
                    longestGap: longestGap
                )
            )
        }

        rows.sort { lhs, rhs in
            switch (lhs.firstChapterIndex, rhs.firstChapterIndex) {
            case let (left?, right?) where left != right:
                return left < right
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                return lhs.character.name < rhs.character.name
            }
        }

        return CharacterMatrix(
            chapters: chapters,
            chapterWordCounts: chapters.map { wordBook.count(of: $0.id) },
            rows: rows
        )
    }

    /// 这一格对应的场景：在场优先，其次提及。点格跳转用。
    public static func node(
        for character: StoryCharacter,
        chapterIndex: Int,
        in project: StoryProject
    ) -> StoryNode? {
        guard project.chapters.indices.contains(chapterIndex) else { return nil }
        let chapterID = project.chapters[chapterIndex].id
        let drafts = project.nodes.filter { $0.status == .draft && $0.chapterID == chapterID }
        if let present = drafts.first(where: { $0.characterIDs.contains(character.id) }) {
            return present
        }
        guard !character.name.isEmpty else { return nil }
        return drafts.first { node in
            node.title.localizedCaseInsensitiveContains(character.name)
                || node.summary.localizedCaseInsensitiveContains(character.name)
                || node.body.localizedCaseInsensitiveContains(character.name)
                || node.annotation.localizedCaseInsensitiveContains(character.name)
        }
    }
}
