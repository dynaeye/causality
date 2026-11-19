import Foundation
import Testing
@testable import CausalityCore

@Suite("人物因果图")
struct CharacterGraphTests {
    @Test("从故事连线推导人物因果线，连线文字带过来")
    func derivesLinksFromStoryEdges() {
        let demo = ConvergenceDemo.make()
        let graph = CharacterGraph.build(project: demo.project)

        #expect(graph.nodes.count == demo.project.characters.count)
        let ahe = graph.nodes.first { $0.character.name == "阿禾" }
        let liang = graph.nodes.first { $0.character.name == "梁婆婆" }
        #expect(ahe != nil)
        #expect(liang != nil)
        #expect(ahe?.sceneCount ?? 0 > 0)
        #expect(liang?.sceneCount ?? 0 > 0)

        let cause = graph.links.first {
            $0.label.contains("旧渡口只有梁婆婆替人捎过家书")
        }
        #expect(cause != nil)
        #expect(cause?.kind == .cause)
        #expect(Set([cause?.from, cause?.to].compactMap { $0 }) == Set([ahe?.id, liang?.id].compactMap { $0 }))
        #expect(cause?.viaTitles.contains("→") == true)
    }

    @Test("同一对人物、同一条原因只归并成一条线")
    func mergesDuplicateLinks() {
        var builder = ProjectBuilder(seed: 77, title: "重复因果")
        let chapter = builder.project.chapters[0].id
        let firstParty = builder.addCharacter(name: "甲")
        let secondParty = builder.addCharacter(name: "乙")
        let first = builder.addNode(title: "一", chapterID: chapter, isEntry: true, characters: [firstParty])
        let second = builder.addNode(title: "二", chapterID: chapter, characters: [secondParty])
        let third = builder.addNode(title: "三", chapterID: chapter, characters: [firstParty])
        let fourth = builder.addNode(title: "四", chapterID: chapter, characters: [secondParty])
        builder.connect(first, to: second, kind: .cause, label: "同一句话")
        builder.connect(third, to: fourth, kind: .cause, label: "同一句话")

        let graph = CharacterGraph.build(project: builder.finalized())
        let links = graph.links.filter { $0.kind == .cause }
        #expect(links.count == 1)
        #expect(links[0].weight == 2)
    }

    @Test("同场共现按场数计权；只靠因果线相连的不算共现")
    func coPresenceWeight() {
        var builder = ProjectBuilder(seed: 81, title: "同场")
        let chapter = builder.project.chapters[0].id
        let firstParty = builder.addCharacter(name: "甲")
        let secondParty = builder.addCharacter(name: "乙")
        let together = builder.addNode(title: "同场一", chapterID: chapter, isEntry: true, characters: [firstParty, secondParty])
        let again = builder.addNode(title: "同场二", chapterID: chapter, characters: [secondParty, firstParty])
        let solo = builder.addNode(title: "甲独场", chapterID: chapter, characters: [firstParty])
        let other = builder.addNode(title: "乙独场", chapterID: chapter, characters: [secondParty])
        builder.connect(solo, to: other, kind: .cause, label: "隔场因果")

        let graph = CharacterGraph.build(project: builder.finalized())
        #expect(graph.coPresenceLinks.count == 1)
        let link = graph.coPresenceLinks[0]
        #expect(Set([link.from, link.to]) == Set([firstParty, secondParty]))
        #expect(link.weight == 2)
        #expect(link.sceneIDs == [together, again])
        #expect(graph.nodes.first { $0.id == firstParty }?.linkCount == 1)
        #expect(graph.links.contains { $0.label == "隔场因果" })
    }

    @Test("同一人物跨两条线时记成自身推进")
    func countsSelfAdvance() {
        var builder = ProjectBuilder(seed: 79, title: "自身推进")
        let chapter = builder.project.chapters[0].id
        let ahe = builder.addCharacter(name: "阿禾")
        let other = builder.addCharacter(name: "旁人")
        let first = builder.addNode(title: "一", chapterID: chapter, isEntry: true, characters: [ahe])
        let second = builder.addNode(title: "二", chapterID: chapter, characters: [ahe])
        let third = builder.addNode(title: "三", chapterID: chapter, characters: [other])
        builder.connect(first, to: second, kind: .cause, label: "她自己想通了")
        builder.connect(second, to: third, kind: .cause, label: "她去找旁人")

        let graph = CharacterGraph.build(project: builder.finalized())
        let node = graph.nodes.first { $0.id == ahe }
        #expect(node?.selfAdvanceCount == 1)
        #expect(graph.links.count == 1)
    }

    @Test("念头卡不参与人物因果")
    func ignoresIdeaCards() {
        var builder = ProjectBuilder(seed: 83, title: "念头")
        let chapter = builder.project.chapters[0].id
        let ahe = builder.addCharacter(name: "阿禾")
        let liang = builder.addCharacter(name: "梁婆婆")
        let first = builder.addNode(title: "正式", chapterID: chapter, isEntry: true, characters: [ahe])
        let idea = builder.addNode(title: "念头", chapterID: chapter, status: .idea, characters: [liang])
        builder.connect(first, to: idea, kind: .cause, label: "还没定")

        let graph = CharacterGraph.build(project: builder.finalized())
        #expect(graph.links.isEmpty)
        #expect(graph.nodes.first { $0.id == liang }?.sceneCount == 0)
        #expect(graph.nodes.first { $0.id == liang }?.hasAppeared == false)
    }
}

@Suite("人物亲属关系")
struct CharacterKinshipTests {
    private func projectWithRelation() throws -> (StoryProject, CharacterID, CharacterID) {
        var builder = ProjectBuilder(seed: 91, title: "亲属")
        let chapter = builder.project.chapters[0].id
        let ahe = builder.addCharacter(name: "阿禾")
        let liang = builder.addCharacter(name: "梁婆婆")
        _ = builder.addNode(title: "一", chapterID: chapter, isEntry: true, characters: [ahe, liang])
        var project = builder.finalized()
        try ProjectEditing.apply(
            ProjectMutations.addRelation(.mentor, from: ahe, to: liang, in: project),
            to: &project
        )
        return (project, ahe, liang)
    }

    @Test("关系存进人物，图上多一条亲属线")
    func relationShowsAsKinLink() throws {
        let (project, ahe, liang) = try projectWithRelation()
        let character = try #require(project.characters.first { $0.id == ahe })
        #expect(character.relations.count == 1)
        #expect(character.relations[0].kind == .mentor)
        #expect(character.relations[0].target == liang)

        let graph = CharacterGraph.build(project: project)
        #expect(graph.kinships.count == 1)
        #expect(graph.kinships[0].from == ahe)
        #expect(graph.kinships[0].to == liang)
        #expect(graph.kinships[0].kind == .mentor)
        // 亲属线不影响因果线。
        #expect(graph.links.isEmpty)
    }

    @Test("重复添加同一条关系只会留一份")
    func duplicateRelationIgnored() throws {
        var (project, ahe, liang) = try projectWithRelation()
        try ProjectEditing.apply(
            ProjectMutations.addRelation(.mentor, from: ahe, to: liang, in: project),
            to: &project
        )
        #expect(project.characters.first { $0.id == ahe }?.relations.count == 1)
    }

    @Test("删掉人物时，指向他的关系一并清掉")
    func deletingCharacterCleansRelations() throws {
        var (project, ahe, liang) = try projectWithRelation()
        try ProjectEditing.apply(
            ProjectMutations.deleteCharacter(liang, in: project),
            to: &project
        )
        #expect(project.characters.count == 1)
        #expect(project.characters[0].relations.isEmpty)
        #expect(CharacterGraph.build(project: project).kinships.isEmpty)
    }

    @Test("旧工程包里没有 relations 也能读")
    func decodesWithoutRelations() throws {
        let json = """
        {"id":"11111111-1111-4111-a111-111111111111","name":"阿禾","summary":"","notes":""}
        """
        let character = try JSONDecoder().decode(StoryCharacter.self, from: Data(json.utf8))
        #expect(character.name == "阿禾")
        #expect(character.relations.isEmpty)
    }
}

@Suite("亲属关系去重")
struct CharacterKinshipDedupTests {
    @Test("两边互写母亲/子女时，图上只有一条线")
    func reciprocalRelationsCollapse() throws {
        var builder = ProjectBuilder(seed: 97, title: "互写")
        let chapter = builder.project.chapters[0].id
        let motherID = builder.addCharacter(name: "梁婆婆")
        let childID = builder.addCharacter(name: "梁子松")
        _ = builder.addNode(title: "一", chapterID: chapter, isEntry: true, characters: [motherID, childID])

        var project = builder.finalized()
        try ProjectEditing.apply(
            ProjectMutations.addRelation(.mother, from: motherID, to: childID, in: project),
            to: &project
        )
        try ProjectEditing.apply(
            ProjectMutations.addRelation(.child, from: childID, to: motherID, in: project),
            to: &project
        )

        let graph = CharacterGraph.build(project: project)
        #expect(graph.kinships.count == 1)
        #expect(graph.kinships[0].kind == .mother)
        // 两份记录仍在人物身上，只是图里合并成一条。
        #expect(project.characters.first { $0.id == motherID }?.relations.count == 1)
        #expect(project.characters.first { $0.id == childID }?.relations.count == 1)
    }
}

@Suite("关系两边的称呼")
struct CharacterKinshipLabelTests {
    private func pair(_ first: RelationKind, _ second: RelationKind) throws -> CharacterKinLink {
        var builder = ProjectBuilder(seed: 101, title: "称呼")
        let chapter = builder.project.chapters[0].id
        let firstID = builder.addCharacter(name: "甲")
        let secondID = builder.addCharacter(name: "乙")
        _ = builder.addNode(title: "一", chapterID: chapter, isEntry: true, characters: [firstID, secondID])
        var project = builder.finalized()
        try ProjectEditing.apply(ProjectMutations.addRelation(first, from: firstID, to: secondID, in: project), to: &project)
        try ProjectEditing.apply(ProjectMutations.addRelation(second, from: secondID, to: firstID, in: project), to: &project)
        let graph = CharacterGraph.build(project: project)
        return try #require(graph.kinships.first)
    }

    @Test("母/子两边都写时显示「母亲/子女」")
    func motherChild() throws {
        let link = try pair(.mother, .child)
        #expect(link.label == "母亲/子女")
    }

    @Test("对称关系显示成「夫妻/夫妻」")
    func spousePair() throws {
        let link = try pair(.spouse, .spouse)
        #expect(link.label == "夫妻/夫妻")
    }

    @Test("兄弟姐妹按长幼显示「兄/弟」")
    func brothers() throws {
        let link = try pair(.elderBrother, .youngerBrother)
        #expect(link.label == "兄/弟")
    }

    @Test("对方没写时只显示这一侧")
    func oneSided() throws {
        var builder = ProjectBuilder(seed: 103, title: "单边")
        let chapter = builder.project.chapters[0].id
        let firstID = builder.addCharacter(name: "甲")
        let secondID = builder.addCharacter(name: "乙")
        _ = builder.addNode(title: "一", chapterID: chapter, isEntry: true, characters: [firstID, secondID])
        var project = builder.finalized()
        try ProjectEditing.apply(ProjectMutations.addRelation(.mentor, from: firstID, to: secondID, in: project), to: &project)
        let link = try #require(CharacterGraph.build(project: project).kinships.first)
        #expect(link.label == "师长")
    }
}
