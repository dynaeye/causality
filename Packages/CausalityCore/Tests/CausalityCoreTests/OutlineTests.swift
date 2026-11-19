import Foundation
import Testing
@testable import CausalityCore

@Suite("大纲推导")
struct OutlineTests {
    @Test("线性剧情保持同级缩进")
    func linearChainKeepsSameLevel() {
        var builder = ProjectBuilder(seed: 7, title: "线性")
        let chapter = builder.project.chapters[0].id
        let first = builder.addNode(title: "一", chapterID: chapter, isEntry: true)
        let second = builder.addNode(title: "二", chapterID: chapter)
        let third = builder.addNode(title: "三", chapterID: chapter)
        builder.connect(first, to: second, kind: .plain, label: "接下来")
        builder.connect(second, to: third, kind: .plain, label: "接下来")

        let outline = OutlineBuilder.build(project: builder.finalized())[0]
        #expect(outline.rows.map(\.indent) == [0, 0, 0])
        #expect(outline.rows.allSatisfy { $0.role == .scene })
        #expect(outline.rows.first?.incoming == nil)
        #expect(outline.rows.compactMap(\.incoming?.label) == ["接下来", "接下来"])
    }

    @Test("分支才增加缩进，汇合点第二次到达变成跳转")
    func branchIndentAndMerge() {
        var builder = ProjectBuilder(seed: 11, title: "分支")
        let chapter = builder.project.chapters[0].id
        let start = builder.addNode(title: "起点", chapterID: chapter, isEntry: true)
        let left = builder.addNode(title: "左路", chapterID: chapter)
        let right = builder.addNode(title: "右路", chapterID: chapter)
        let merge = builder.addNode(title: "汇合", chapterID: chapter)
        builder.connect(start, to: left, kind: .choice, label: "选左")
        builder.connect(start, to: right, kind: .choice, label: "选右")
        builder.connect(left, to: merge, kind: .plain, label: "左路抵达")
        builder.connect(right, to: merge, kind: .plain, label: "右路抵达")

        let outline = OutlineBuilder.build(project: builder.finalized())[0]
        #expect(outline.rows.map(\.role) == [.scene, .scene, .scene, .scene, .revisit])
        #expect(outline.rows.map(\.indent) == [0, 1, 1, 1, 1])
        #expect(outline.rows.map(\.nodeTitle) == ["起点", "左路", "汇合", "右路", "汇合"])
        #expect(outline.sceneCount == 4)
        #expect(outline.revisitCount == 1)
        #expect(outline.rows.first { $0.nodeID == merge && $0.role == .scene }?.incoming?.label == "左路抵达")
        #expect(outline.rows.last?.incoming?.label == "右路抵达")
    }

    @Test("回环被截断成跳转，不会无限展开")
    func cycleBecomesRevisit() {
        var builder = ProjectBuilder(seed: 13, title: "回环")
        let chapter = builder.project.chapters[0].id
        let first = builder.addNode(title: "一", chapterID: chapter, isEntry: true)
        let second = builder.addNode(title: "二", chapterID: chapter)
        builder.connect(first, to: second, kind: .plain, label: "往下")
        builder.connect(second, to: first, kind: .condition, label: "回到起点")

        let outline = OutlineBuilder.build(project: builder.finalized())[0]
        #expect(outline.rows.count == 3)
        #expect(outline.rows.map(\.role) == [.scene, .scene, .revisit])
        #expect(outline.rows.last?.nodeTitle == "一")
    }

    @Test("跨章连线在本章是跳转，在目标章还原文")
    func crossChapterJump() {
        var builder = ProjectBuilder(seed: 17, title: "跨章")
        let firstChapter = builder.project.chapters[0].id
        let secondChapter = builder.addChapter(title: "第二章")
        let entry = builder.addNode(title: "开场", chapterID: firstChapter, isEntry: true)
        let next = builder.addNode(title: "第二章的场景", chapterID: secondChapter, isEntry: true)
        builder.connect(entry, to: next, kind: .cause, label: "转到下一章")

        let outlines = OutlineBuilder.build(project: builder.finalized())
        #expect(outlines.count == 2)
        #expect(outlines[0].rows.map(\.role) == [.scene, .crossChapter])
        #expect(outlines[0].rows[1].targetChapterID == secondChapter)
        #expect(outlines[1].rows.map(\.role) == [.scene])
        #expect(outlines[1].rows[0].nodeTitle == "第二章的场景")
    }

    @Test("遍历完入口后补上未接线的节点")
    func detachedNodesAppearLast() {
        var builder = ProjectBuilder(seed: 19, title: "未接线")
        let chapter = builder.project.chapters[0].id
        let entry = builder.addNode(title: "入口", chapterID: chapter, isEntry: true)
        _ = builder.addNode(title: "孤岛", chapterID: chapter)
        let followUp = builder.addNode(title: "孤岛的后续", chapterID: chapter)
        let orphan = builder.project.nodes.first { $0.title == "孤岛" }?.id
        if let orphan {
            builder.connect(orphan, to: followUp, kind: .plain, label: "自己往下")
        }

        let outline = OutlineBuilder.build(project: builder.finalized())[0]
        #expect(outline.rows.map(\.nodeTitle) == ["入口", "孤岛", "孤岛的后续"])
        #expect(outline.rows.map(\.origin) == [.entry, .detached, .edge])
        #expect(outline.detachedCount == 1)
        #expect(entry != followUp)
    }

    @Test("同级顺序表决定并列分支的先后")
    func chapterOrderBreaksTies() {
        var builder = ProjectBuilder(seed: 23, title: "顺序")
        let chapter = builder.project.chapters[0].id
        let start = builder.addNode(title: "起点", chapterID: chapter, isEntry: true)
        let alpha = builder.addNode(title: "甲", chapterID: chapter)
        let beta = builder.addNode(title: "乙", chapterID: chapter)
        builder.connect(start, to: beta, kind: .choice, label: "先写乙")
        builder.connect(start, to: alpha, kind: .choice, label: "再写甲")

        // 顺序表按 甲、乙 排，乙虽先连线仍排在甲之后。
        let outline = OutlineBuilder.build(project: builder.finalized())[0]
        let branchTitles = outline.rows.filter { $0.indent == 1 }.map(\.nodeTitle)
        #expect(branchTitles == ["甲", "乙"])
    }

    @Test("灵感卡不进大纲")
    func ideaCardsStayOutOfOutline() {
        var builder = ProjectBuilder(seed: 29, title: "灵感")
        let chapter = builder.project.chapters[0].id
        _ = builder.addNode(title: "正式场景", chapterID: chapter, isEntry: true)
        _ = builder.addNode(title: "一个想法", status: .idea)

        let outline = OutlineBuilder.build(project: builder.finalized())[0]
        #expect(outline.rows.map(\.nodeTitle) == ["正式场景"])
    }
}
