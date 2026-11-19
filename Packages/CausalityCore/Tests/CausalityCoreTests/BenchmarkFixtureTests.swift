import Foundation
import Testing
@testable import CausalityCore

@Suite("基准样本")
struct BenchmarkFixtureTests {
    @Test("固定种子下两次生成完全一致")
    func deterministic() throws {
        let first = try ProjectCoding.encode(BenchmarkFixture.make())
        let second = try ProjectCoding.encode(BenchmarkFixture.make())
        #expect(first == second)
        #expect(first.count > 100_000)
    }

    @Test("规模与结构覆盖到位")
    func scaleAndCoverage() {
        let project = BenchmarkFixture.make()
        let facts = BenchmarkFixture.facts(of: project)
        #expect(facts.nodeCount == 500)
        #expect(facts.edgeCount == 800)
        #expect(facts.chapterCount == 12)
        #expect(facts.branchNodes > 0)
        #expect(facts.mergeNodes > 0)
        #expect(facts.cycleEdges >= 4)
        #expect(facts.orphanNodes >= 6)
        #expect(facts.crossChapterEdges >= 12)
        #expect(facts.revisitRows > 0)
        #expect(facts.crossChapterRows > 0)
        #expect(facts.detachedRows >= 6)
    }

    @Test("基准样本结构自洽")
    func validates() {
        let issues = ProjectValidator.issues(in: BenchmarkFixture.make())
        #expect(issues.isEmpty)
    }

    @Test("500 节点大纲推导在预算内")
    func outlineBuildsQuickly() {
        let project = BenchmarkFixture.make()
        let started = Date()
        let outlines = OutlineBuilder.build(project: project)
        let elapsed = Date().timeIntervalSince(started)
        #expect(outlines.count == 12)
        #expect(elapsed < 0.5)
    }

    @Test("500 节点字数统计在预算内")
    func wordCountsBuildQuickly() {
        let project = BenchmarkFixture.make()
        _ = WordCount.Book(project: project) // 预热一次，排除首次分配的开销
        let started = Date()
        let book = WordCount.Book(project: project)
        let elapsed = Date().timeIntervalSince(started)
        #expect(book.sceneCount > 0)
        #expect(book.total > 0)
        #expect(elapsed < 0.02)
    }

    @Test("河灯样本结构自洽且两条路可达")
    func riverLanternSampleIsValid() {
        let script = ConvergenceDemo.make()
        #expect(ProjectValidator.issues(in: script.project).isEmpty)
        let rows = OutlineBuilder.build(project: script.project).flatMap(\.rows)
        #expect(rows.filter { $0.nodeID == script.ending && $0.role == .scene }.count == 1)
        #expect(rows.filter { $0.nodeID == script.ending && $0.role == .revisit }.count == 1)
    }
}
