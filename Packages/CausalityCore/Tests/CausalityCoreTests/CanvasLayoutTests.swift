import Foundation
import Testing
@testable import CausalityCore

@Suite("故事图排布")
struct CanvasLayoutTests {
    private func project() throws -> StoryProject {
        var builder = ProjectBuilder(seed: 5, title: "排布")
        let first = builder.project.chapters[0].id
        let second = builder.addChapter(title: "第二章")
        for index in 1...7 {
            builder.addNode(
                title: "S\(index)",
                chapterID: index <= 4 ? first : second
            )
        }
        return builder.finalized()
    }

    @Test("阅读顺序按章、按章内顺序表")
    func readingOrder() throws {
        let project = try project()
        let order = CanvasLayout.readingOrder(of: project).compactMap { project.node($0)?.title }
        #expect(order == ["S1", "S2", "S3", "S4", "S5", "S6", "S7"])
    }

    @Test("列数随画布宽度增长")
    func columnsScaleWithWidth() {
        #expect(CanvasLayout.columns(forWidth: 0) == 1)
        #expect(CanvasLayout.columns(forWidth: 300) == 1)
        #expect(CanvasLayout.columns(forWidth: 600) == 2)
        #expect(CanvasLayout.columns(forWidth: 1200) == 5)
        #expect(CanvasLayout.columns(forWidth: 1800) == 7)
        #expect(CanvasLayout.columns(forWidth: 2400) > CanvasLayout.columns(forWidth: 1200))
    }

    @Test("蛇形：第一行左到右，第二行右到左")
    func serpentineAlternates() throws {
        let project = try project()
        let points = CanvasLayout.serpentine(project: project, columns: 3)
        let byTitle = Dictionary(uniqueKeysWithValues: project.nodes.compactMap { node in
            points[node.id].map { (node.title, $0) }
        })

        let step = 210.0 + 110.0
        let rowGap = 240.0
        #expect(byTitle["S1"]?.x == 120)
        #expect(byTitle["S3"]?.x == 120 + 2 * step)
        #expect(byTitle["S1"]?.y == byTitle["S3"]?.y)

        // 第二行从右往左：S4 在最右，S6 在最左，且落在下一行
        #expect(byTitle["S4"]?.x == byTitle["S3"]?.x)
        #expect(byTitle["S6"]?.x == 120)
        #expect((byTitle["S4"]?.y ?? 0) > (byTitle["S1"]?.y ?? 0))

        // 第三行又回到左往右
        #expect(byTitle["S7"]?.x == 120)
        #expect(byTitle["S7"]?.y == 120 + 2 * rowGap)
    }

    @Test("相邻两张最多隔一个格子")
    func neighboursStayClose() throws {
        let project = try project()
        let points = CanvasLayout.serpentine(project: project, columns: 3)
        let step = 210.0 + 110.0
        let order = CanvasLayout.readingOrder(of: project)
        for (from, to) in zip(order, order.dropFirst()) {
            guard let start = points[from], let end = points[to] else { continue }
            let distance = abs(start.x - end.x) + abs(start.y - end.y)
            #expect(distance <= step + 1)
        }
    }

    @Test("重排只为挪了位置的卡生成操作")
    func arrangeProducesMinimalOperations() throws {
        let project = try project()
        let operations = CanvasLayout.arrange(project: project)
        // 每张卡一条 setCanvasPoint
        #expect(operations.count == project.nodes.count)

        var arranged = project
        try ProjectEditing.apply(operations, to: &arranged)
        #expect(CanvasLayout.arrange(project: arranged).isEmpty)
    }
}
