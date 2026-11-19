import Foundation
import Testing
@testable import CausalityCore

@Suite("写作顺序")
struct WritingOrderTests {
    private func makeProject() -> StoryProject {
        let first = Chapter(title: "第一章")
        let second = Chapter(title: "第二章")
        var sceneA = StoryNode(title: "A", chapterID: first.id)
        sceneA.isEntry = true
        let sceneB = StoryNode(title: "B", chapterID: first.id)
        let sceneC = StoryNode(title: "C", chapterID: first.id)
        let idea = StoryNode(status: .idea, title: "念头")
        let sceneD = StoryNode(title: "D", chapterID: second.id)
        let sceneE = StoryNode(title: "E", chapterID: second.id)
        let loose = StoryNode(title: "未分章的一场")

        var firstChapter = first
        // B 在前、A 在后，B 重复一次，C 不在顺序表里，念头混在顺序表里。
        firstChapter.order = [sceneB.id, sceneA.id, sceneB.id, idea.id]
        var secondChapter = second
        secondChapter.order = [sceneE.id, sceneD.id]

        return StoryProject(
            title: "写作顺序",
            chapters: [firstChapter, secondChapter],
            nodes: [sceneA, sceneB, sceneC, idea, sceneD, sceneE, loose],
            edges: [StoryEdge(from: sceneA.id, to: sceneC.id, kind: .plain)]
        )
    }

    @Test("章内按 chapter.order，缺的补在章末，每张 draft 恰好一次")
    func followsChapterOrder() {
        let project = makeProject()
        let scenes = WritingOrder.scenes(in: project)
        #expect(scenes.map(\.node.title) == ["B", "A", "C", "E", "D", "未分章的一场"])
        #expect(scenes.map(\.chapterNumber) == [1, 1, 1, 2, 2, 0])
        #expect(scenes.map(\.sceneNumber) == [1, 2, 3, 1, 2, 1])
        #expect(Set(scenes.map(\.id)).count == scenes.count)
        #expect(scenes.allSatisfy { $0.node.status == .draft })
    }

    @Test("灵感卡不进写作顺序")
    func omitsIdeas() {
        let project = makeProject()
        let titles = WritingOrder.scenes(in: project).map(\.node.title)
        #expect(!titles.contains("念头"))
    }

    @Test("写作顺序跟着顺序表，大纲跟着入口与出边")
    func canDifferFromOutline() {
        let project = makeProject()
        let writing = WritingOrder.scenes(in: project).map(\.node.title)
        let outline = OutlineBuilder.build(project: project)
            .flatMap(\.rows)
            .filter { $0.role == .scene }
            .map(\.nodeTitle)
        #expect(writing.prefix(3) == ["B", "A", "C"])
        #expect(outline.prefix(3) == ["A", "C", "B"])
    }
}
