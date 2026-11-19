import Foundation
import Testing
@testable import CausalityCore

@Suite("v2a 场景字段与项目字段")
struct SchemaV2Tests {
    @Test("旧包缺字段时补默认值，不炸")
    func decodesV1() throws {
        let json = """
        {
          "schemaVersion": 1,
          "id": "11111111-1111-4111-a111-111111111111",
          "title": "旧包",
          "nodes": [{
            "id": "22222222-2222-4222-a222-222222222222",
            "kind": "event",
            "status": "draft",
            "title": "第一场"
          }]
        }
        """
        let project = try ProjectCoding.decode(Data(json.utf8))
        #expect(project.title == "旧包")
        let node = try #require(project.nodes.first)
        #expect(node.storyTimeLabel == "")
        #expect(node.pov == nil)
        #expect(node.sceneType == nil)
        #expect(node.tension == nil)
        #expect(node.targetWords == nil)
        #expect(node.writingState == nil)
        #expect(project.cardGroupOverrides.isEmpty)
        #expect(project.workingRouteEndingID == nil)
    }

    @Test("新字段能存能读，保存后版本是 2")
    func roundTripsNewFields() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-v2-\(UUID().uuidString)", isDirectory: true)
        let url = root.appendingPathComponent("v2.\(ProjectPackage.fileExtension)", isDirectory: true)

        var project = StoryProject.empty(title: "新字段")
        var node = StoryNode(title: "第三日黄昏", chapterID: project.chapters.first?.id)
        node.storyTimeLabel = "第三日黄昏"
        node.sceneType = .dialogue
        node.tension = 4
        node.targetWords = 1200
        node.writingState = .revising
        let character = StoryCharacter(name: "阿禾")
        try ProjectEditing.apply(ProjectMutations.appendCharacter(character, to: project), to: &project)
        node.pov = character.id
        try ProjectEditing.apply(ProjectMutations.appendNode(node, to: project), to: &project)
        project.cardGroupOverrides[node.id.rawValue.uuidString] = "mergeAbove"
        project.workingRouteEndingID = node.id

        try ProjectPackage.save(project, to: url)
        let loaded = try ProjectPackage.load(from: url).project

        #expect(loaded.schemaVersion == 2)
        let read = try #require(loaded.nodes.first { $0.id == node.id })
        #expect(read.storyTimeLabel == "第三日黄昏")
        #expect(read.sceneType == .dialogue)
        #expect(read.tension == 4)
        #expect(read.targetWords == 1200)
        #expect(read.writingState == .revising)
        #expect(read.pov == character.id)
        #expect(loaded.cardGroupOverrides[node.id.rawValue.uuidString] == "mergeAbove")
        #expect(loaded.workingRouteEndingID == node.id)
    }

    @Test("删掉卡时，工作路线与并列组覆盖一起清掉")
    func deleteClearsReferences() throws {
        var project = StoryProject.empty(title: "引用")
        let node = StoryNode(title: "会被删")
        try ProjectEditing.apply(ProjectMutations.appendNode(node, to: project), to: &project)
        project.workingRouteEndingID = node.id
        project.cardGroupOverrides[node.id.rawValue.uuidString] = "ownGroup"

        try ProjectEditing.apply(ProjectMutations.deleteNode(node.id, in: project), to: &project)
        #expect(project.workingRouteEndingID == nil)
        #expect(project.cardGroupOverrides.isEmpty)
    }
}
