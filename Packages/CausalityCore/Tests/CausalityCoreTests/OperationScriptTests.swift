import Foundation
import Testing
@testable import CausalityCore

@Suite("编辑脚本")
struct OperationScriptTests {
    private func decode(_ json: String) throws -> OperationScript {
        try JSONDecoder().decode(OperationScript.self, from: Data(json.utf8))
    }

    private func sampleProject() throws -> StoryProject {
        var builder = ProjectBuilder(seed: 11, title: "测试")
        let chapter = builder.project.chapters[0].id
        builder.addNode(title: "开场", chapterID: chapter, isEntry: true)
        builder.addNode(title: "中段", chapterID: chapter)
        builder.addCharacter(name: "阿禾")
        builder.addPlace(name: "旧渡口")
        builder.addSetting(title: "引息诀")
        return builder.finalized()
    }

    @Test("按名字建卡、连线、改卡")
    func addConnectUpdate() throws {
        var project = try sampleProject()
        let script = try decode("""
        { "version": 1, "ops": [
          { "op": "addCard", "chapter": "第一章", "title": "结尾", "body": "回信到了。", "after": "中段" },
          { "op": "connect", "from": "中段", "to": "结尾", "label": "回信" },
          { "op": "updateCard", "card": "结尾", "summary": "收束", "kind": "ending" },
          { "op": "setEntry", "card": "开场", "isEntry": true }
        ] }
        """)
        let results = try OperationRunner.apply(script, to: &project)

        #expect(results.count == 4)
        let cards = project.chapters[0].order.compactMap { project.node($0) }
        #expect(cards.map(\.title) == ["开场", "中段", "结尾"])
        #expect(project.edges.count == 1)
        #expect(project.edges[0].label == "回信")
        let last = try #require(project.nodes.first { $0.title == "结尾" })
        #expect(last.kind == .ending)
        #expect(last.summary == "收束")
        #expect(results[0].createdID != nil)
        #expect(results[1].createdID != nil)
    }

    @Test("跨章移动、删卡连同连线一起走")
    func moveAndDelete() throws {
        var project = try sampleProject()
        let first = try decode("""
        { "ops": [
          { "op": "addChapter", "title": "第二章" },
          { "op": "connect", "from": "开场", "to": "中段", "label": "接着" },
          { "op": "moveCard", "card": "中段", "chapter": "第二章" },
          { "op": "deleteCard", "card": "中段" }
        ] }
        """)
        try OperationRunner.apply(first, to: &project)

        #expect(project.chapters.count == 2)
        #expect(project.chapters[1].order.isEmpty)
        #expect(project.nodes.contains { $0.title == "中段" } == false)
        #expect(project.edges.isEmpty)
    }

    @Test("人物、地点、设定的创建、引用与删除")
    func entities() throws {
        var project = try sampleProject()
        let script = try decode("""
        { "ops": [
          { "op": "addCharacter", "name": "梁婆婆", "summary": "撑船人" },
          { "op": "addRelation", "from": "阿禾", "to": "梁婆婆", "kind": "friend" },
          { "op": "addCard", "chapter": "第一章", "title": "渡口", "places": ["旧渡口"], "settings": ["引息诀"] },
          { "op": "attachSetting", "setting": "引息诀", "card": "开场" },
          { "op": "updateSetting", "setting": "引息诀", "text": "依呼吸引火", "confirmed": true },
          { "op": "addPlace", "name": "河街" },
          { "op": "updatePlace", "place": "河街", "summary": "集日摆摊" }
        ] }
        """)
        try OperationRunner.apply(script, to: &project)

        let ahe = try #require(project.characters.first { $0.name == "阿禾" })
        let liang = try #require(project.characters.first { $0.name == "梁婆婆" })
        #expect(ahe.relations.contains { $0.target == liang.id && $0.kind == .friend })

        let setting = try #require(project.settings.first { $0.title == "引息诀" })
        #expect(setting.isConfirmed)
        #expect(setting.text == "依呼吸引火")
        #expect(setting.attachedNodeIDs.count == 2)
        // 两边都要写：节点侧的 settingIDs 是大纲、导出与界面读的那一份
        let opening = try #require(project.nodes.first { $0.title == "开场" })
        let crossing = try #require(project.nodes.first { $0.title == "渡口" })
        #expect(opening.settingIDs == [setting.id])
        #expect(crossing.settingIDs == [setting.id])
        #expect(crossing.placeIDs.count == 1)

        let street = try #require(project.places.first { $0.name == "河街" })
        #expect(street.summary == "集日摆摊")
    }

    @Test("锁定的设定不能删，错误带序号")
    func lockedSetting() throws {
        var project = try sampleProject()
        let script = try decode("""
        { "ops": [
          { "op": "updateSetting", "setting": "引息诀", "locked": true },
          { "op": "deleteSetting", "setting": "引息诀" }
        ] }
        """)
        do {
            _ = try OperationRunner.apply(script, to: &project)
            Issue.record("锁定后删除应当失败")
        } catch let error as ScriptError {
            #expect(error.index == 1)
            #expect(error.op == "deleteSetting")
            #expect(error.reason.contains("锁定"))
        }
    }

    @Test("找不到的引用会报错，且指明是哪一条")
    func missingReference() throws {
        var project = try sampleProject()
        let script = try decode("""
        { "ops": [
          { "op": "addCard", "title": "序" },
          { "op": "connect", "from": "开场", "to": "不存在的卡" }
        ] }
        """)
        do {
            _ = try OperationRunner.apply(script, to: &project)
            Issue.record("引用不存在的卡片应当失败")
        } catch let error as ScriptError {
            #expect(error.index == 1)
            #expect(error.op == "connect")
            #expect(error.reason.contains("不存在的卡"))
        }
    }

    @Test("不认识的 op 在解码时就拒绝")
    func unknownOp() {
        #expect(throws: DecodingError.self) {
            _ = try decode("""
            { "ops": [ { "op": "explode", "title": "x" } ] }
            """)
        }
    }
}
