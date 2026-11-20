import Foundation

/// 普通 Markdown 导入：`#` 项目名、`##` 章、`###` 场，其余段落进正文。
///
/// 没有 `###` 时，一章里的段落并成一场；没有 `##` 时，整篇并成「第一章」。
/// 人物 / 地点 / 设定只认文内的同名资料段，不再预置示例库。
public enum ProseMarkdown {
    private struct SceneDraft {
        var title: String
        var lines: [String] = []

        var body: String {
            lines.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private struct ChapterDraft {
        var title: String
        var scenes: [SceneDraft] = []
    }

    public static func makeProject(
        fromMarkdown text: String,
        title fallbackTitle: String = "",
        seed: UInt64 = 7
    ) throws -> StoryProject {
        let lines = text.components(separatedBy: .newlines)
        var docTitle = ""
        var logline = ""
        var chapters: [ChapterDraft] = []
        var currentChapter: Int?
        var currentScene: Int?
        var skippingLibrarySection = false
        var sawTitle = false
        var looseParagraphs: [String] = []

        func startChapter(_ title: String) {
            chapters.append(ChapterDraft(title: title))
            currentChapter = chapters.count - 1
            currentScene = nil
        }

        func ensureChapter() {
            if currentChapter == nil {
                startChapter(CoreText.localize("第一章"))
            }
        }

        func startScene(_ title: String) {
            ensureChapter()
            guard let chapter = currentChapter else { return }
            chapters[chapter].scenes.append(SceneDraft(title: title))
            currentScene = chapters[chapter].scenes.count - 1
        }

        func ensureScene() {
            guard currentScene == nil else { return }
            ensureChapter()
            guard let chapter = currentChapter else { return }
            let title = chapters[chapter].title.isEmpty ? CoreText.localize("开场") : chapters[chapter].title
            startScene(title)
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("# ") {
                let value = plain(String(line.dropFirst(2)))
                if !sawTitle {
                    docTitle = value
                    sawTitle = true
                    skippingLibrarySection = false
                } else {
                    skippingLibrarySection = false
                    startChapter(value)
                }
                continue
            }
            if line.hasPrefix("## ") {
                let value = plain(String(line.dropFirst(3)))
                if MarkdownLibrary.isLibraryTitle(value) {
                    skippingLibrarySection = true
                    currentChapter = nil
                    currentScene = nil
                } else {
                    skippingLibrarySection = false
                    startChapter(value)
                }
                continue
            }
            if line.hasPrefix("### ") || line.hasPrefix("#### ") {
                guard !skippingLibrarySection else { continue }
                let drop = line.hasPrefix("#### ") ? 5 : 4
                startScene(plain(String(line.dropFirst(drop))))
                continue
            }
            guard !skippingLibrarySection else { continue }

            if currentChapter == nil, currentScene == nil, logline.isEmpty, line.hasPrefix("**") {
                logline = plain(line)
                continue
            }
            if currentChapter == nil {
                looseParagraphs.append(plainParagraph(line))
            } else {
                ensureScene()
                guard let chapter = currentChapter, let scene = currentScene else { continue }
                chapters[chapter].scenes[scene].lines.append(plainParagraph(line))
            }
        }

        if !looseParagraphs.isEmpty || chapters.isEmpty {
            if !looseParagraphs.isEmpty || chapters.isEmpty {
                startChapter(CoreText.localize("第一章"))
                startScene(docTitle.isEmpty ? CoreText.localize("开场") : docTitle)
                if let chapter = currentChapter, let scene = currentScene {
                    chapters[chapter].scenes[scene].lines = looseParagraphs
                }
            }
        }

        chapters = chapters
            .map { chapter in
                var value = chapter
                value.scenes = value.scenes.filter { !$0.body.isEmpty }
                return value
            }
            .filter { !$0.scenes.isEmpty }
        guard !chapters.isEmpty else {
            throw StoryboardMarkdown.ImportError.noContent
        }

        var base = StoryProject.empty(title: fallbackTitle.isEmpty ? (docTitle.isEmpty ? "未命名" : docTitle) : fallbackTitle)
        base.logline = String(logline.prefix(400))
        var builder = ProjectBuilder(project: base, seed: seed)
        let library = MarkdownLibrary.parse(text: text, builder: &builder)

        var chain: [(node: NodeID, lead: String)] = []
        for chapter in chapters {
            let chapterID = builder.addChapter(title: chapter.title)
            for scene in chapter.scenes {
                let body = scene.body
                let summary = firstSentence(body)
                let nodeID = builder.addNode(
                    title: scene.title.isEmpty ? chapter.title : scene.title,
                    summary: String(summary.prefix(120)),
                    body: body,
                    chapterID: chapterID,
                    isEntry: chain.isEmpty,
                    characters: library.characters.filter { body.contains($0.name) }.map(\.id),
                    places: library.places.filter { body.contains($0.name) }.map(\.id)
                )
                for setting in library.settings where body.contains(setting.title) {
                    builder.attach(setting.id, to: nodeID)
                }
                chain.append((node: nodeID, lead: summary))
            }
        }

        for (previous, next) in zip(chain, chain.dropFirst()) {
            builder.connect(
                previous.node,
                to: next.node,
                kind: .plain,
                label: String(previous.lead.prefix(28))
            )
        }
        builder.apply(CanvasLayout.arrange(project: builder.project))
        return builder.finalized()
    }

    private static func firstSentence(_ text: String) -> String {
        let sentence = text
            .components(separatedBy: CharacterSet(charactersIn: "。！？!?\n"))
            .first ?? text
        return sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func plainParagraph(_ line: String) -> String {
        var value = line
        while value.hasPrefix(">") {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespaces)
        }
        return plain(value)
    }

    private static func plain(_ text: String) -> String {
        var value = text
        for token in ["**", "__", "`"] {
            value = value.replacingOccurrences(of: token, with: "")
        }
        return value.trimmingCharacters(in: .whitespaces)
    }
}
