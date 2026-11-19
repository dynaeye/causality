import Foundation
import Testing
@testable import CausalityCore

@Suite("试玩")
struct PlaythroughTests {
    @Test("河灯：沿守密线走到结局，步数与累计字数")
    func riverLanternWalk() throws {
        let project = ConvergenceDemo.make().project
        var play = try #require(PlaythroughEngine.start(in: project))
        #expect(play.current?.node.title == "阿禾捞起河灯")
        #expect(play.stepCount == 1)

        let first = try #require(play.current?.options.first)
        play = try #require(PlaythroughEngine.choose(first.edgeID, in: play, project: project))
        #expect(play.current?.node.title == "梁婆婆认出河灯")

        let keepSecret = try #require(play.current?.options.first { $0.label == ConvergenceDemo.keepSecretLabel })
        play = try #require(PlaythroughEngine.choose(keepSecret.edgeID, in: play, project: project))
        #expect(play.current?.node.title == "梁婆婆交出半封旧信")

        let toEnding = try #require(play.current?.options.first)
        play = try #require(PlaythroughEngine.choose(toEnding.edgeID, in: play, project: project))
        #expect(play.current?.node.title == "旧渡口的信")
        #expect(play.finished)
        #expect(!play.deadEnd)
        #expect(play.stepCount == 4)
        #expect(play.cumulativeWords == 115)
    }

    @Test("回退三步后与开局逐字段一致")
    func backToStart() throws {
        let project = ConvergenceDemo.make().project
        let start = try #require(PlaythroughEngine.start(in: project))
        var play = start
        for _ in 0..<3 {
            let option = try #require(play.current?.options.first)
            play = try #require(PlaythroughEngine.choose(option.edgeID, in: play, project: project))
        }
        #expect(play.stepCount == 4)
        for _ in 0..<3 {
            play = try #require(PlaythroughEngine.back(play, project: project))
        }
        #expect(play == start)
    }

    @Test("断头停在原地并标记 deadEnd")
    func deadEnd() throws {
        var builder = ProjectBuilder(seed: 71, title: "断头")
        let chapter = builder.project.chapters[0].id
        let start = builder.addNode(title: "起点", body: "正文", chapterID: chapter, isEntry: true)
        let dead = builder.addNode(title: "死路", body: "正文", chapterID: chapter)
        builder.connect(start, to: dead, kind: .plain)
        let project = builder.finalized()
        var play = try #require(PlaythroughEngine.start(in: project))
        let option = try #require(play.current?.options.first)
        play = try #require(PlaythroughEngine.choose(option.edgeID, in: play, project: project))
        #expect(play.current?.node.title == "死路")
        #expect(play.deadEnd)
        #expect(!play.finished)
    }

    @Test("面包屑跳回中间一步")
    func jumpBack() throws {
        let project = ConvergenceDemo.make().project
        var play = try #require(PlaythroughEngine.start(in: project))
        let first = try #require(play.current?.options.first)
        play = try #require(PlaythroughEngine.choose(first.edgeID, in: play, project: project))
        let second = try #require(play.current?.options.first)
        play = try #require(PlaythroughEngine.choose(second.edgeID, in: play, project: project))
        let jumped = try #require(PlaythroughEngine.jump(to: 1, in: play, project: project))
        #expect(jumped.stepCount == 2)
        #expect(jumped.current?.node.title == "梁婆婆认出河灯")
    }

    @Test("同一工程两次开局一致")
    func deterministic() {
        let project = ConvergenceDemo.make().project
        #expect(PlaythroughEngine.start(in: project) == PlaythroughEngine.start(in: project))
    }
}
