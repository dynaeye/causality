import Foundation
import Testing
@testable import CausalityCore

@Suite("线索")
struct ThreadTests {
    private func thread(on script: ConvergenceDemo.Script, roles: [(NodeID, ThreadRole)]) -> StoryThread {
        StoryThread(
            name: "伏笔·河灯底下的字",
            kind: .foreshadow,
            entries: roles.map { ThreadEntry(nodeID: $0.0, role: $0.1) }
        )
    }

    @Test("埋点与收点按章序排成脊柱")
    func spineOrder() {
        let script = ConvergenceDemo.make()
        let value = thread(on: script, roles: [(script.lantern, .plant), (script.ending, .payoff), (script.grandaunt, .reinforce)])
        let points = ThreadSpine.points(for: value, in: script.project)
        #expect(points.map(\.entry.role) == [.plant, .reinforce, .payoff])
        #expect(points.map(\.chapterNumber) == [1, 1, 1])
    }

    @Test("有埋无收报 N16；补齐收点后消失")
    func auditUnpaidThread() throws {
        var project = ConvergenceDemo.make().project
        let script = ConvergenceDemo.make()
        let unpaid = thread(on: script, roles: [(script.lantern, .plant)])
        try ProjectEditing.apply(ProjectMutations.appendThread(unpaid, to: project), to: &project)
        #expect(NarrativeAudit.run(project: project).contains { $0.rule == "N16" })

        let paid = thread(on: script, roles: [(script.lantern, .plant), (script.ending, .payoff)])
        try ProjectEditing.apply(
            ProjectMutations.updateThread(unpaid.id, in: project) { $0.entries = paid.entries },
            to: &project
        )
        #expect(!NarrativeAudit.run(project: project).contains { $0.rule == "N16" })
    }

    @Test("收点排在埋点之前报 N17")
    func auditPayoffBeforePlant() throws {
        var project = ConvergenceDemo.make().project
        let script = ConvergenceDemo.make()
        let reversed = thread(on: script, roles: [(script.lantern, .payoff), (script.ending, .plant)])
        try ProjectEditing.apply(ProjectMutations.appendThread(reversed, to: project), to: &project)
        #expect(NarrativeAudit.run(project: project).contains { $0.rule == "N17" })
    }

    @Test("线索跟着工程包往返")
    func roundTrip() throws {
        var project = ConvergenceDemo.make().project
        let script = ConvergenceDemo.make()
        let value = thread(on: script, roles: [(script.lantern, .plant), (script.ending, .payoff)])
        try ProjectEditing.apply(ProjectMutations.appendThread(value, to: project), to: &project)
        let data = try ProjectCoding.encode(project)
        let decoded = try ProjectCoding.decode(data)
        #expect(decoded.threads == project.threads)
    }

    @Test("大纲 Markdown 带线索附录")
    func markdownAppendix() throws {
        var project = ConvergenceDemo.make().project
        let script = ConvergenceDemo.make()
        let value = thread(on: script, roles: [(script.lantern, .plant), (script.ending, .payoff)])
        try ProjectEditing.apply(ProjectMutations.appendThread(value, to: project), to: &project)
        let markdown = OutlineMarkdown.render(project: project)
        #expect(markdown.contains("## 线索"))
        #expect(markdown.contains("伏笔 · 伏笔·河灯底下的字"))
        #expect(markdown.contains("- 埋：第一章 · 阿禾捞起河灯"))
        #expect(markdown.contains("- 收：第一章 · 旧渡口的信"))
    }
}
