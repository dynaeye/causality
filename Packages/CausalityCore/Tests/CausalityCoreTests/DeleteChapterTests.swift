import Foundation
import Testing
@testable import CausalityCore

@Suite("删除章节")
struct DeleteChapterTests {
    /// 两章：第一章有两张卡和一条连线、一个画布坐标；第二章一张卡。
    private func makeProject() throws -> (project: StoryProject, first: ChapterID, second: ChapterID, nodes: [NodeID]) {
        var project = StoryProject.empty(title: "删章")
        let first = ChapterID()
        let second = ChapterID()
        try ProjectEditing.apply(ProjectMutations.appendChapter(Chapter(id: first, title: "第一章"), to: project), to: &project)
        try ProjectEditing.apply(ProjectMutations.appendChapter(Chapter(id: second, title: "第二章"), to: project), to: &project)

        let one = StoryNode(title: "求仙", chapterID: first, isEntry: true)
        let two = StoryNode(title: "入门", chapterID: first)
        let three = StoryNode(title: "后续", chapterID: second)
        for node in [one, two, three] {
            try ProjectEditing.apply(ProjectMutations.appendNode(node, to: project), to: &project)
        }
        project.edges = [StoryEdge(from: one.id, to: two.id, kind: .cause, label: "跨过扫帚")]
        project.canvas[one.id] = CanvasPoint(x: 10, y: 20)
        return (project, first, second, [one.id, two.id, three.id])
    }

    @Test("删章时章里的卡、连线、画布坐标一起删，别的章不动")
    func deletesItsOwnCards() throws {
        let fixture = try makeProject()
        var project = fixture.project
        let operations = ProjectMutations.deleteChapter(fixture.first, in: project)
        try ProjectEditing.apply(operations, to: &project)

        #expect(project.chapters.map(\.title) == ["第二章"])
        #expect(project.nodes.map(\.title) == ["后续"])
        #expect(project.edges.isEmpty)
        #expect(project.canvas.isEmpty)
        #expect(project.node(fixture.nodes[2]) != nil)
    }

    @MainActor
    @Test("撤销一次，章、卡、连线、坐标都回来")
    func undoRestoresEverything() throws {
        let fixture = try makeProject()
        let original = fixture.project
        let editor = StoryEditor(project: original)
        try editor.apply(ProjectMutations.deleteChapter(fixture.first, in: original), name: "删除章节")

        #expect(editor.project.nodes.count == 1)
        #expect(try editor.undo())
        #expect(editor.project == original)
    }
}
