import Foundation
import Testing
@testable import CausalityCore

@Suite("分支梗概")
struct BranchSynopsisTests {
    /// 入口 → 分岔 → 两条分支 → 汇合 → 结局。
    private func diamond() throws -> (StoryProject, [String: NodeID]) {
        var builder = ProjectBuilder(seed: 31, title: "梗概")
        let chapter = builder.project.chapters[0].id
        let entry = builder.addNode(title: "开场", summary: "雨刚停，阿禾带着行囊进镇。", chapterID: chapter, isEntry: true)
        let fork = builder.addNode(title: "分岔", summary: "梁婆婆认出河灯。", chapterID: chapter)
        let left = builder.addNode(title: "守密", summary: "阿禾答应守密。", chapterID: chapter)
        let right = builder.addNode(title: "问镇民", summary: "众人认出纸张。", chapterID: chapter)
        let join = builder.addNode(title: "渡口", summary: "阿禾读懂母亲的缘由。", chapterID: chapter)
        let ending = builder.addNode(title: "旧渡口的信", kind: .ending, summary: "回信交还给了梁婆婆。", chapterID: chapter)

        builder.connect(entry, to: fork, kind: .cause, label: "灯底的字")
        builder.connect(fork, to: left, kind: .choice, label: "答应守密")
        builder.connect(fork, to: right, kind: .choice, label: "拿灯问人")
        builder.connect(left, to: join, kind: .plain)
        builder.connect(right, to: join, kind: .plain)
        builder.connect(join, to: ending, kind: .plain)
        return (builder.finalized(), [
            "entry": entry, "fork": fork, "left": left, "right": right, "join": join, "ending": ending,
        ])
    }

    @Test("列出结局与路上卡数")
    func endings() throws {
        let (project, ids) = try diamond()
        let list = BranchSynopsis.endings(in: project)
        #expect(list.count == 1)
        #expect(list[0].title == "旧渡口的信")
        #expect(list[0].id == ids["ending"])
        #expect(list[0].cardCount == 6)
    }

    @Test("分段模式：前缀、两条分支、结局各一块，汇合只讲一次")
    func segments() throws {
        let (project, ids) = try diamond()
        let synopsis = BranchSynopsis.make(project: project, endingID: ids["ending"]!, mode: .segments)
        #expect(synopsis.blocks.map(\.label) == ["开始", "答应守密", "拿灯问人", "汇合"])

        let prefix = synopsis.blocks[0]
        #expect(prefix.nodeIDs == [ids["entry"]!, ids["fork"]!])
        #expect(prefix.text.contains("雨刚停"))
        #expect(prefix.text.contains("梁婆婆认出河灯"))

        // 分支块只讲分叉后的那一场，不再重复前缀
        #expect(synopsis.blocks[1].nodeIDs == [ids["left"]!])
        #expect(synopsis.blocks[2].nodeIDs == [ids["right"]!])

        // 汇合与结局合在最后一块里，且只出现一次
        let tail = synopsis.blocks[3]
        #expect(tail.nodeIDs == [ids["join"]!, ids["ending"]!])
        #expect(synopsis.text.components(separatedBy: "阿禾读懂").count == 2)
    }

    @Test("逐条模式：每条路径一整段，标签取分叉处的选项文案")
    func perPath() throws {
        let (project, ids) = try diamond()
        let synopsis = BranchSynopsis.make(project: project, endingID: ids["ending"]!, mode: .perPath)
        #expect(synopsis.blocks.count == 2)
        #expect(Set(synopsis.blocks.map(\.label)) == ["答应守密", "拿灯问人"])
        #expect(synopsis.blocks.allSatisfy { $0.nodeIDs.count == 5 })
        #expect(synopsis.blocks[0].text.contains("若答应守密") || synopsis.blocks[1].text.contains("若答应守密"))
    }

    @Test("每块最多四句，超出的场次记在 omitted 里")
    func sentenceLimit() throws {
        var builder = ProjectBuilder(seed: 32, title: "长线")
        let chapter = builder.project.chapters[0].id
        let entry = builder.addNode(title: "S1", summary: "第一场。", chapterID: chapter, isEntry: true)
        var previous = entry
        for index in 2...7 {
            let node = builder.addNode(title: "S\(index)", summary: "第 \(index) 场。", chapterID: chapter)
            builder.connect(previous, to: node, kind: .plain)
            previous = node
        }
        let ending = builder.addNode(title: "收尾", kind: .ending, summary: "结束。", chapterID: chapter)
        builder.connect(previous, to: ending, kind: .plain)

        let project = builder.finalized()
        let synopsis = BranchSynopsis.make(project: project, endingID: ending, mode: .perPath)
        let block = try #require(synopsis.blocks.first)
        #expect(block.sentences.count == 4)
        #expect(block.omitted == 4)
        #expect(block.text.contains("下面还有 4 场"))
    }

    @Test("摘要为空时退到标题")
    func fallsBackToTitle() throws {
        var builder = ProjectBuilder(seed: 33, title: "空摘要")
        let chapter = builder.project.chapters[0].id
        let entry = builder.addNode(title: "只有标题的一场", chapterID: chapter, isEntry: true)
        let ending = builder.addNode(title: "结束", kind: .ending, summary: "收束。", chapterID: chapter)
        builder.connect(entry, to: ending, kind: .plain)

        let project = builder.finalized()
        let synopsis = BranchSynopsis.make(project: project, endingID: ending)
        #expect(synopsis.blocks[0].text.contains("只有标题的一场。"))
    }

    @Test("从某张卡能看到后面的结局与步数")
    func reachable() throws {
        let (project, ids) = try diamond()
        let list = EndingReach.from(ids["fork"]!, in: project)
        #expect(list.count == 1)
        #expect(list[0].endingID == ids["ending"])
        #expect(list[0].steps == 3)

        let fromEntry = EndingReach.from(ids["entry"]!, in: project)
        #expect(fromEntry[0].steps == 4)
        #expect(EndingReach.from(ids["ending"]!, in: project).first?.steps == 0)
    }

    @Test("角标：卡数、字数、选择点、独占卡与步数")
    func endingStats() throws {
        let (project, ids) = try diamond()
        let synopsis = BranchSynopsis.make(project: project, endingID: ids["ending"]!)
        #expect(synopsis.stats.choiceCount == 1)
        #expect(synopsis.stats.exclusiveCount == 6)
        #expect(synopsis.stats.shortestSteps == 4)
        #expect(synopsis.stats.longestSteps == 4)
        #expect(!synopsis.stats.thin)
    }

    @Test("两个结局各只有一张独占卡时判太薄，共同章报必读墙")
    func thinEndingsAndSharedChapter() throws {
        var builder = ProjectBuilder(seed: 55, title: "两个结局")
        let chapter = builder.project.chapters[0].id
        let entry = builder.addNode(title: "开场", summary: "开场。", chapterID: chapter, isEntry: true)
        let fork = builder.addNode(title: "分岔", summary: "分岔。", chapterID: chapter)
        let left = builder.addNode(title: "结局甲", kind: .ending, summary: "甲。", chapterID: chapter)
        let right = builder.addNode(title: "结局乙", kind: .ending, summary: "乙。", chapterID: chapter)
        builder.connect(entry, to: fork, kind: .plain)
        builder.connect(fork, to: left, kind: .choice, label: "向左")
        builder.connect(fork, to: right, kind: .choice, label: "向右")

        let project = builder.finalized()
        let synopsis = BranchSynopsis.make(project: project, endingID: left)
        #expect(synopsis.stats.exclusiveCount == 1)
        #expect(synopsis.stats.thin)
        #expect(BranchSynopsis.sharedChapters(in: project).map(\.title) == ["第一章"])
    }

    @Test("同一工程两次生成完全一致")
    func deterministic() throws {
        let (project, ids) = try diamond()
        let first = BranchSynopsis.make(project: project, endingID: ids["ending"]!)
        let second = BranchSynopsis.make(project: project, endingID: ids["ending"]!)
        #expect(first == second)
        #expect(first.text == second.text)
    }

    @Test("分支超过 24 条时截断")
    func pathCap() throws {
        var builder = ProjectBuilder(seed: 57, title: "很多分支")
        let chapter = builder.project.chapters[0].id
        let entry = builder.addNode(title: "开场", summary: "开场。", chapterID: chapter, isEntry: true)
        let ending = builder.addNode(title: "收束", kind: .ending, summary: "收束。", chapterID: chapter)
        for index in 0..<30 {
            let branch = builder.addNode(title: "分支 \(index)", summary: "第 \(index) 条。", chapterID: chapter)
            builder.connect(entry, to: branch, kind: .choice, label: "走 \(index)")
            builder.connect(branch, to: ending, kind: .plain)
        }
        let synopsis = BranchSynopsis.make(project: builder.finalized(), endingID: ending, mode: .perPath)
        #expect(synopsis.truncated)
        #expect(synopsis.blocks.count <= 24)
    }
}
