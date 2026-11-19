import Foundation
import Testing
@testable import CausalityCore

@Suite("通往结局的路径")
struct StoryRouteTests {
    /// 入口 → 分岔 A（选项）→ 两条路 → 汇合「旧渡口」；另有一条与结局无关的支线。
    private func diamond() throws -> (StoryProject, [String: NodeID]) {
        var builder = ProjectBuilder(seed: 21, title: "分岔")
        let chapter = builder.project.chapters[0].id
        let entry = builder.addNode(title: "开场", chapterID: chapter, isEntry: true)
        let fork = builder.addNode(title: "分岔", kind: .choice, chapterID: chapter)
        let left = builder.addNode(title: "左手", chapterID: chapter)
        let right = builder.addNode(title: "右手", chapterID: chapter)
        let ending = builder.addNode(title: "旧渡口", kind: .ending, chapterID: chapter)
        let aside = builder.addNode(title: "支线", chapterID: chapter)

        builder.connect(entry, to: fork, kind: .cause, label: "因为入口")
        builder.connect(fork, to: left, kind: .choice, label: "走左")
        builder.connect(fork, to: right, kind: .choice, label: "走右")
        builder.connect(left, to: ending, kind: .plain, label: "左到渡口")
        builder.connect(right, to: ending, kind: .plain, label: "右到渡口")
        builder.connect(aside, to: fork, kind: .plain, label: "旁路")
        return (builder.finalized(), ["entry": entry, "fork": fork, "left": left, "right": right, "ending": ending, "aside": aside])
    }

    @Test("两条分支都算在通往结局的路上，无关节点排除")
    func pathsToEnding() throws {
        let (project, ids) = try diamond()
        let route = StoryRoute.paths(to: ids["ending"]!, in: project)

        #expect(route.nodeIDs == [ids["entry"]!, ids["fork"]!, ids["left"]!, ids["right"]!, ids["ending"]!])
        #expect(!route.nodeIDs.contains(ids["aside"]!))
        #expect(route.edgeIDs.count == 5)
        #expect(!route.isEmpty)
    }

    @Test("只看这条路时，大纲里不出现范围外的卡")
    func outlineFiltered() throws {
        let (project, ids) = try diamond()
        let route = StoryRoute.paths(to: ids["ending"]!, in: project)
        let index = project.makeIndex()

        let all = OutlineBuilder.build(project: project, index: index)
        let filtered = OutlineBuilder.build(project: project, index: index, nodes: route.nodeIDs)
        let allTitles = all.flatMap { $0.rows.map(\.nodeTitle) }
        let filteredTitles = filtered.flatMap { $0.rows.map(\.nodeTitle) }

        #expect(allTitles.contains("支线"))
        #expect(!filteredTitles.contains("支线"))
        #expect(filteredTitles.contains("旧渡口"))
        // 汇合处会多一行跳转，去重后正好是路上的五张卡
        #expect(Set(filteredTitles) == ["开场", "分岔", "左手", "右手", "旧渡口"])
    }

    @Test("单路线 Markdown 带说明，且不含无关卡与灵感卡")
    func routeMarkdown() throws {
        var (project, ids) = try diamond()
        let idea = StoryNode(status: .idea, title: "一个念头")
        try ProjectEditing.apply(ProjectMutations.appendNode(idea, to: project), to: &project)

        let route = StoryRoute.paths(to: ids["ending"]!, in: project)
        let markdown = OutlineMarkdown.render(project: project, route: route)

        #expect(markdown.contains("> 只含通往「旧渡口」的路径。"))
        #expect(markdown.contains("### 旧渡口"))
        #expect(!markdown.contains("支线"))
        #expect(!markdown.contains("一个念头"))
        #expect(markdown.contains("选项：走左"))
        #expect(markdown.contains("选项：走右"))
    }

    @Test("没有结局或没有入口时给空结果，不崩")
    func emptyCases() throws {
        var builder = ProjectBuilder(seed: 22, title: "空")
        let chapter = builder.project.chapters[0].id
        let only = builder.addNode(title: "唯一一张", chapterID: chapter)
        let project = builder.finalized()

        let missing = StoryRoute.paths(to: NodeID(), in: project)
        #expect(missing.isEmpty)

        let selfRoute = StoryRoute.paths(to: only, in: project)
        #expect(selfRoute.nodeIDs == [only])
    }
}
