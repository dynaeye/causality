import Foundation
import Testing
@testable import CausalityCore

@Suite("叙事体检")
struct NarrativeAuditTests {
    private func rules(_ project: StoryProject) -> [String] {
        NarrativeAudit.run(project: project).map(\.rule)
    }

    @Test("河灯：断头、结局还有去向、无条件分叉、主线未标注与类型探针")
    func riverLantern() {
        let project = ConvergenceDemo.make().project
        let findings = NarrativeAudit.run(project: project)
        #expect(findings.map(\.rule) == ["N01", "N03", "N08", "N15", "N20"])
        #expect(findings.filter { $0.severity == .error }.count == 2)
    }

    @Test("没有结局时 N10 / N11 被抑制，线性结构报 N21")
    func linearProjectWithoutEnding() {
        var builder = ProjectBuilder(seed: 29, title: "线性")
        let chapter = builder.project.chapters[0].id
        let first = builder.addNode(title: "一", body: "正文", chapterID: chapter, isEntry: true)
        let second = builder.addNode(title: "二", body: "正文", chapterID: chapter)
        let third = builder.addNode(title: "三", body: "正文", chapterID: chapter)
        builder.connect(first, to: second, kind: .plain)
        builder.connect(second, to: third, kind: .plain)
        let findings = NarrativeAudit.run(project: builder.finalized())
        #expect(findings.map(\.rule) == ["N01", "N12", "N21"])
        #expect(!findings.contains { $0.rule == "N10" || $0.rule == "N11" })
    }

    @Test("忽略一条后不再出现；--all 能看到")
    func waiverHidesFinding() throws {
        var project = ConvergenceDemo.make().project
        let ending = try #require(project.nodes.first { $0.title == "旧渡口的信" })
        let waiver = AuditWaiver(ruleID: "N03", subjectID: ending.id.rawValue.uuidString, reason: "这条支线是尾声")
        try ProjectEditing.apply(
            ProjectMutations.addAuditWaiver(waiver, to: project),
            to: &project
        )
        #expect(!NarrativeAudit.run(project: project).contains { $0.rule == "N03" })
        #expect(NarrativeAudit.waivedFindings(in: project).map(\.rule) == ["N03"])
        #expect(NarrativeAudit.run(project: project, includeWaived: true).contains { $0.rule == "N03" })
    }

    @Test("N09：一圈互相可达又没有出口")
    func cycleWithoutOutlet() {
        var builder = ProjectBuilder(seed: 31, title: "环")
        let chapter = builder.project.chapters[0].id
        let first = builder.addNode(title: "一", chapterID: chapter, isEntry: true)
        let second = builder.addNode(title: "二", chapterID: chapter)
        builder.connect(first, to: second, kind: .plain)
        builder.connect(second, to: first, kind: .plain)
        let project = builder.finalized()
        #expect(rules(project).contains("N09"))
    }

    @Test("N10：一条长路旁边挂一个很近的结局")
    func endingTooClose() {
        var builder = ProjectBuilder(seed: 37, title: "近结局")
        let chapter = builder.project.chapters[0].id
        let start = builder.addNode(title: "起点", chapterID: chapter, isEntry: true)
        let early = builder.addNode(title: "早结局", kind: .ending, chapterID: chapter)
        let two = builder.addNode(title: "二", chapterID: chapter)
        let three = builder.addNode(title: "三", chapterID: chapter)
        let four = builder.addNode(title: "四", chapterID: chapter)
        let late = builder.addNode(title: "远结局", kind: .ending, chapterID: chapter)
        builder.connect(start, to: early, kind: .choice)
        builder.connect(start, to: two, kind: .choice)
        builder.connect(two, to: three, kind: .plain)
        builder.connect(three, to: four, kind: .plain)
        builder.connect(four, to: late, kind: .plain)
        #expect(rules(builder.finalized()).contains("N10"))
    }

    @Test("N11：有一条去向走不到任何结局")
    func branchNeverReachesEnding() {
        var builder = ProjectBuilder(seed: 41, title: "死路")
        let chapter = builder.project.chapters[0].id
        let start = builder.addNode(title: "起点", chapterID: chapter, isEntry: true)
        let dead = builder.addNode(title: "死路", chapterID: chapter)
        let good = builder.addNode(title: "活路", chapterID: chapter)
        let ending = builder.addNode(title: "结局", kind: .ending, chapterID: chapter)
        builder.connect(start, to: dead, kind: .choice)
        builder.connect(start, to: good, kind: .choice)
        builder.connect(good, to: ending, kind: .plain)
        #expect(rules(builder.finalized()).contains("N11"))
    }

    @Test("N18：同名已确认设定正文不一致")
    func conflictingSettings() throws {
        var project = ConvergenceDemo.make().project
        let first = try #require(project.settings.first)
        let second = Setting(
            title: first.title,
            text: "另一种说法。",
            isConfirmed: true,
            attachedNodeIDs: first.attachedNodeIDs
        )
        try ProjectEditing.apply(
            ProjectMutations.appendSetting(second, to: project),
            to: &project
        )
        #expect(rules(project).contains("N18"))
    }

    @Test("N19：人物在章序列中间连续两章不出场")
    func characterGap() throws {
        var builder = ProjectBuilder(seed: 43, title: "断层")
        let firstChapter = builder.project.chapters[0].id
        let character = builder.addCharacter(name: "阿禾")
        _ = builder.addNode(
            title: "第一场",
            chapterID: firstChapter,
            isEntry: true,
            characters: [character]
        )

        var middle = Chapter(title: "第二章")
        builder.apply(ProjectMutations.appendChapter(middle, to: builder.project))
        _ = builder.addNode(title: "第二场", chapterID: middle.id)

        var third = Chapter(title: "第三章")
        builder.apply(ProjectMutations.appendChapter(third, to: builder.project))
        _ = builder.addNode(title: "第三场", chapterID: third.id)

        var fourth = Chapter(title: "第四章")
        builder.apply(ProjectMutations.appendChapter(fourth, to: builder.project))
        _ = builder.addNode(
            title: "第四场",
            chapterID: fourth.id,
            characters: [character]
        )

        #expect(rules(builder.finalized()).contains("N19"))
    }

    @Test("500 节点体检在预算内")
    func benchmarkPerformance() {
        let project = BenchmarkFixture.make()
        _ = NarrativeAudit.run(project: project)
        let started = Date()
        _ = NarrativeAudit.run(project: project)
        #expect(Date().timeIntervalSince(started) < 0.15)
    }

    @Test("N07：两条边指向同一张卡且都没有条件")
    func fakeChoice() {
        var builder = ProjectBuilder(seed: 47, title: "伪选择")
        let chapter = builder.project.chapters[0].id
        let start = builder.addNode(title: "起点", body: "正文", chapterID: chapter, isEntry: true)
        let target = builder.addNode(title: "同一张卡", body: "正文", chapterID: chapter)
        let ending = builder.addNode(title: "结局", kind: .ending, body: "正文", chapterID: chapter)
        builder.connect(start, to: target, kind: .choice, label: "选项甲")
        builder.connect(start, to: target, kind: .choice, label: "选项乙")
        builder.connect(target, to: ending, kind: .plain)
        #expect(rules(builder.finalized()).contains("N07"))
    }
}
