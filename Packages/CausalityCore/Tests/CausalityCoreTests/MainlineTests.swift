import Foundation
import Testing
@testable import CausalityCore

@Suite("主线推导")
struct MainlineTests {
    /// 入口 → 求仙 →（分岔）入门 / 打坐 → 结局
    private func makeProject(markBranch: Bool = false) throws -> (project: StoryProject, entry: NodeID, main: EdgeID, branch: EdgeID, ending: NodeID) {
        var project = StoryProject.empty(title: "主线")
        let chapter = Chapter(title: "第一章")
        try ProjectEditing.apply(ProjectMutations.appendChapter(chapter, to: project), to: &project)

        let entry = StoryNode(title: "入口", chapterID: chapter.id, isEntry: true)
        let fork = StoryNode(title: "求仙", chapterID: chapter.id)
        let mainLine = StoryNode(title: "入门", chapterID: chapter.id)
        let side = StoryNode(title: "打坐", chapterID: chapter.id)
        let ending = StoryNode(kind: .ending, title: "结局", chapterID: chapter.id)
        for node in [entry, fork, mainLine, side, ending] {
            try ProjectEditing.apply(ProjectMutations.appendNode(node, to: project), to: &project)
        }

        var mainID = EdgeID()
        var branchID = EdgeID()
        let edges = [
            StoryEdge(from: entry.id, to: fork.id, kind: .cause, label: "上山"),
            StoryEdge(from: fork.id, to: mainLine.id, kind: .choice, label: "入门", isMainline: !markBranch),
            StoryEdge(from: fork.id, to: side.id, kind: .choice, label: "打坐", isMainline: markBranch),
            StoryEdge(from: mainLine.id, to: ending.id, kind: .cause, label: "走到最后"),
            StoryEdge(from: side.id, to: ending.id, kind: .cause, label: "也回去"),
        ]
        mainID = edges[1].id
        branchID = edges[2].id
        project.edges = edges
        return (project, entry.id, mainID, branchID, ending.id)
    }

    @Test("不标注时按第一条出边走，也是主线")
    func defaultFirstEdge() throws {
        let fixture = try makeProject(markBranch: false)
        let line = Mainline.derive(in: fixture.project)
        #expect(line.contains(edge: fixture.main))
        #expect(!line.contains(edge: fixture.branch))
        #expect(line.contains(node: fixture.ending))
        #expect(line.nodeIDs.count == 4)
    }

    @Test("标注之后跟着标记走")
    func followsMarkedEdge() throws {
        let fixture = try makeProject(markBranch: true)
        let line = Mainline.derive(in: fixture.project)
        #expect(line.contains(edge: fixture.branch))
        #expect(!line.contains(edge: fixture.main))
        #expect(line.isExplicit)
    }

    @Test("同一选择点只留一条主线出边")
    func marksAreExclusive() throws {
        let fixture = try makeProject(markBranch: false)
        var project = fixture.project
        let operations = ProjectMutations.setMainline(fixture.branch, in: project)
        try ProjectEditing.apply(operations, to: &project)

        let outgoing = project.edges.filter { $0.from == project.edges.first { $0.id == fixture.branch }?.from }
        #expect(outgoing.filter(\.isMainline).count == 1)
        #expect(project.edge(fixture.branch)?.isMainline == true)
        #expect(project.edge(fixture.main)?.isMainline == false)
    }

    @Test("旧工程包没有 isMainline 也能解出来")
    func decodesLegacyEdge() throws {
        let json = """
        {"id":"8B0B0B78-580B-4F84-A0BE-8D7D4E9D8E2A","from":"A1A1A1A1-1111-4111-8111-111111111111",
         "to":"B2B2B2B2-2222-4222-8222-222222222222","kind":"cause","label":"","condition":"","annotation":""}
        """
        let edge = try JSONDecoder().decode(StoryEdge.self, from: Data(json.utf8))
        #expect(edge.isMainline == false)
        #expect(edge.kind == .cause)
    }
}
