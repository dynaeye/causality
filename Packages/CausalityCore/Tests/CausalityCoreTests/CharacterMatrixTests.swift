import Foundation
import Testing
@testable import CausalityCore

@Suite("人物出场矩阵")
struct CharacterMatrixTests {
    @Test("河灯：梁婆婆两章在场、阿禾只在第一章，列头带字数")
    func riverLanternMatrix() throws {
        let project = ConvergenceDemo.make().project
        let matrix = CharacterMatrixBuilder.build(project: project)
        #expect(matrix.chapters.count == 2)
        #expect(matrix.chapterWordCounts.count == 2)
        #expect(matrix.chapterWordCounts[0] > 0)
        let ahe = try #require(matrix.rows.first { $0.character.name == "阿禾" })
        let liang = try #require(matrix.rows.first { $0.character.name == "梁婆婆" })
        #expect(ahe.cells[0] == .present)
        #expect(ahe.cells[1] == .absent)
        #expect(liang.cells[0] == .present)
        #expect(liang.cells[1] == .present)
        #expect(liang.firstChapterIndex == 0)
    }

    @Test("只被提及与尚未写的章")
    func mentionedAndUnwritten() throws {
        var builder = ProjectBuilder(seed: 93, title: "矩阵")
        let firstChapter = builder.project.chapters[0].id
        let ahe = builder.addCharacter(name: "阿禾")
        let liang = builder.addCharacter(name: "梁婆婆")
        let scene = builder.addNode(
            title: "第一场",
            summary: "梁婆婆在渡口等船。",
            body: "阿禾来了。",
            chapterID: firstChapter,
            isEntry: true,
            characters: [ahe]
        )
        var second = Chapter(title: "第二章")
        builder.apply(ProjectMutations.appendChapter(second, to: builder.project))
        _ = second
        _ = scene
        // 第二章没有任何正式场景：所有人物在这一列都是「尚未写」。
        var third = Chapter(title: "第三章")
        builder.apply(ProjectMutations.appendChapter(third, to: builder.project))
        _ = third

        let project = builder.finalized()
        let matrix = CharacterMatrixBuilder.build(project: project)
        let aheRow = try #require(matrix.rows.first { $0.character.name == "阿禾" })
        let liangRow = try #require(matrix.rows.first { $0.character.name == "梁婆婆" })
        #expect(aheRow.cells[0] == .present)
        #expect(liangRow.cells[0] == .mentioned)
        #expect(liangRow.cells[1] == .unwritten)
        let liangCharacter = try #require(project.characters.first { $0.id == liang })
        #expect(CharacterMatrixBuilder.node(for: liangCharacter, chapterIndex: 0, in: project)?.title == "第一场")
    }

    @Test("首次出场排序与最长空档")
    func orderingAndGap() throws {
        var builder = ProjectBuilder(seed: 95, title: "空档")
        let first = builder.project.chapters[0].id
        let early = builder.addCharacter(name: "早")
        let late = builder.addCharacter(name: "晚")
        let start = builder.addNode(title: "一", chapterID: first, isEntry: true, characters: [early])
        _ = start
        for title in ["二", "三"] {
            var chapter = Chapter(title: title)
            builder.apply(ProjectMutations.appendChapter(chapter, to: builder.project))
            _ = chapter
        }
        let fourth = Chapter(title: "四")
        builder.apply(ProjectMutations.appendChapter(fourth, to: builder.project))
        builder.addNode(title: "四的一场", chapterID: fourth.id, characters: [early, late])

        let project = builder.finalized()
        let matrix = CharacterMatrixBuilder.build(project: project)
        #expect(matrix.rows.first?.character.name == "早")
        let earlyRow = try #require(matrix.rows.first { $0.character.name == "早" })
        #expect(earlyRow.firstChapterIndex == 0)
        #expect(earlyRow.lastChapterIndex == 3)
        #expect(earlyRow.longestGap == 2)
        #expect(matrix.rows.last?.character.name == "晚")
    }
}
