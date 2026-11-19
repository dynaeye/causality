import Foundation
import Testing
@testable import CausalityCore

@Suite("索引按章取卡")
struct ProjectIndexCacheTests {
    private func project() throws -> StoryProject {
        var builder = ProjectBuilder(seed: 41, title: "取卡")
        let first = builder.project.chapters[0].id
        let second = builder.addChapter(title: "第二章")
        for index in 1...6 {
            builder.addNode(
                title: "S\(index)",
                summary: "第 \(index) 场。",
                chapterID: index <= 3 ? first : second
            )
        }
        return builder.finalized()
    }

    @Test("按章取卡遵守章内顺序表")
    func followsChapterOrder() throws {
        var project = try project()
        let chapter = project.chapters[0]
        // 把顺序表倒过来，取卡也要跟着倒
        try ProjectEditing.apply(
            ProjectMutations.updateChapter(chapter.id, in: project) { value in
                value.order.reverse()
            },
            to: &project
        )
        let index = project.makeIndex()
        let titles = index.nodes(in: chapter.id).compactMap(\.title)
        let expected = project.chapter(chapter.id)!.order.compactMap { project.node($0)?.title }
        #expect(titles == expected)
    }

    @Test("缓存结果与逐次过滤排序一致")
    func matchesManualOrdering() throws {
        let project = try project()
        let index = project.makeIndex()
        for chapter in project.chapters {
            let orders = Dictionary(uniqueKeysWithValues: chapter.order.enumerated().map { ($0.element, $0.offset) })
            let manual = project.nodes
                .filter { $0.chapterID == chapter.id }
                .sorted { lhs, rhs in
                    let left = orders[lhs.id] ?? Int.max
                    let right = orders[rhs.id] ?? Int.max
                    if left != right { return left < right }
                    if lhs.title != rhs.title { return lhs.title < rhs.title }
                    return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
                }
            #expect(index.nodes(in: chapter.id) == manual)
        }
    }

    @Test("连问一百次也不重新建索引")
    func repeatedLookupsAreCheap() throws {
        let project = try project()
        let index = project.makeIndex()
        let chapter = project.chapters[0].id
        let start = DispatchTime.now().uptimeNanoseconds
        var count = 0
        for _ in 0..<500 {
            count += index.nodes(in: chapter).count
        }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        #expect(count == 1500)
        #expect(ms < 50)
    }
}
