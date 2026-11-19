import Foundation
import Testing
@testable import CausalityCore

@Suite("字数统计")
struct WordCountTests {
    @Test("纯中文按字算，标点与空白不算")
    func chinese() {
        #expect(WordCount.count("雨刚停，玩家带着行囊进镇。") == 11)
        #expect(WordCount.count("雨 刚 停") == 3)
        #expect(WordCount.count("雨刚停\n\n下一段。") == 6)
    }

    @Test("英文按词算")
    func english() {
        #expect(WordCount.count("Rain stops, she walks in.") == 5)
        #expect(WordCount.count("one-two-three") == 3)
    }

    @Test("中英混排各按各的算")
    func mixed() {
        #expect(WordCount.count("阿禾 say hello 之后走了。") == 8)
    }

    @Test("全角空格、emoji 各算一个")
    func specialCharacters() {
        #expect(WordCount.count("阿禾　走") == 3)
        #expect(WordCount.count("阿禾😀") == 3)
    }

    @Test("四级统计同源")
    func aggregates() throws {
        var project = StoryProject.empty(title: "字数")
        let chapter = Chapter(title: "第一章")
        try ProjectEditing.apply(ProjectMutations.appendChapter(chapter, to: project), to: &project)
        var node = StoryNode(title: "A", chapterID: chapter.id)
        node.body = "一二三。"
        try ProjectEditing.apply(ProjectMutations.appendNode(node, to: project), to: &project)

        #expect(WordCount.count(of: node) == 3)
        #expect(WordCount.count(of: chapter.id, in: project) == 3)
        #expect(WordCount.total(in: project) == 3)
    }

    @Test("一次遍历的字数表与四级函数对得上")
    func bookSnapshot() throws {
        var project = StoryProject.empty(title: "字数表")
        let chapter = Chapter(title: "第一章")
        try ProjectEditing.apply(ProjectMutations.appendChapter(chapter, to: project), to: &project)

        var scene = StoryNode(title: "A", chapterID: chapter.id)
        scene.body = "雨刚停，玩家带着行囊进镇。"
        try ProjectEditing.apply(ProjectMutations.appendNode(scene, to: project), to: &project)

        var idea = StoryNode(status: .idea, title: "念头")
        idea.body = "一个还没写下来的念头。"
        try ProjectEditing.apply(ProjectMutations.appendNode(idea, to: project), to: &project)

        let book = WordCount.Book(project: project)
        #expect(book.count(of: scene.id) == WordCount.count(of: scene))
        #expect(book.count(of: idea.id) == WordCount.count(of: idea))
        #expect(book.count(of: chapter.id) == WordCount.count(of: chapter.id, in: project))
        #expect(book.total == WordCount.total(in: project))
        #expect(book.sceneCount == 1)
    }

    @Test("路线字数与章、全书同口径：灵感卡不计")
    func routeCountsDraftOnly() throws {
        var project = StoryProject.empty(title: "路线字数")
        var scene = StoryNode(title: "A", isEntry: true)
        scene.body = "一二三。"
        try ProjectEditing.apply(ProjectMutations.appendNode(scene, to: project), to: &project)

        var ending = StoryNode(kind: .ending, title: "结局")
        ending.body = "四五。"
        try ProjectEditing.apply(ProjectMutations.appendNode(ending, to: project), to: &project)

        var idea = StoryNode(status: .idea, title: "废稿念头")
        idea.body = "不该计入路线的正文。"
        try ProjectEditing.apply(ProjectMutations.appendNode(idea, to: project), to: &project)

        let route = StoryRoute(endingID: ending.id, nodeIDs: [scene.id, ending.id, idea.id])
        #expect(WordCount.count(of: route, in: project) == 5)
        #expect(WordCount.Book(project: project).count(of: route) == WordCount.count(of: route, in: project))
    }
}
