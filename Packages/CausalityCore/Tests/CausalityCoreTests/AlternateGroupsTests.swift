import Foundation
import Testing
@testable import CausalityCore

@Suite("故事板并列组")
struct AlternateGroupsTests {
    @Test("河灯：梁婆婆下方两条分支，在结局处闭合")
    func riverLanternGroup() throws {
        let project = ConvergenceDemo.make().project
        let chapter = try #require(project.chapters.first)
        let groups = AlternateGroups.compute(chapter: chapter, project: project)
        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(project.node(group.forkNodeID)?.title == "梁婆婆认出河灯")
        #expect(group.branchNodeIDs.count == 2)
        #expect(group.memberNodeIDs.count == 2)
        #expect(project.node(group.closeNodeID ?? NodeID())?.title == "旧渡口的信")
        #expect(Set(group.branchByNode.values) == [0, 1])
    }

    @Test("手动 ownGroup 后不再成组")
    func overrideHidesGroup() throws {
        var project = ConvergenceDemo.make().project
        let chapter = try #require(project.chapters.first)
        let group = try #require(AlternateGroups.compute(chapter: chapter, project: project).first)
        try ProjectEditing.apply(
            ProjectMutations.setCardGroupOverride(group.forkNodeID, value: "ownGroup", in: project),
            to: &project
        )
        #expect(AlternateGroups.compute(chapter: chapter, project: project).isEmpty)
    }

    @Test("分支不汇合时组开到章末")
    func openEndedGroup() {
        var builder = ProjectBuilder(seed: 61, title: "不汇合")
        let chapter = builder.project.chapters[0].id
        let fork = builder.addNode(title: "分岔", body: "正文", chapterID: chapter, isEntry: true)
        let left = builder.addNode(title: "左", body: "正文", chapterID: chapter)
        let right = builder.addNode(title: "右", body: "正文", chapterID: chapter)
        let tail = builder.addNode(title: "尾", body: "正文", chapterID: chapter)
        builder.connect(fork, to: left, kind: .choice, label: "左")
        builder.connect(fork, to: right, kind: .choice, label: "右")
        builder.connect(right, to: tail, kind: .plain)

        let project = builder.finalized()
        let chapterValue = project.chapters[0]
        let groups = AlternateGroups.compute(chapter: chapterValue, project: project)
        #expect(groups.count == 1)
        #expect(groups[0].closeNodeID == nil)
        #expect(Set(groups[0].memberNodeIDs) == Set([left, right, tail]))
    }
}
