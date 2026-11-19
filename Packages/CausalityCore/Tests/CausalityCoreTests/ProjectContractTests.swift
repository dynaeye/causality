import Foundation
import Testing
@testable import CausalityCore

@Suite("导出契约")
struct ProjectContractTests {
    private func jsonObject(_ project: StoryProject) throws -> [String: Any] {
        let data = try ProjectCoding.encode(project)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    @Test("字段齐全的工程通过契约")
    func completeProjectPasses() throws {
        let data = try ProjectCoding.encode(ConvergenceDemo.make().project)
        #expect(ProjectContract.missingFields(in: data).isEmpty)
    }

    @Test("删掉顶层字段会点名 logline")
    func missingTopLevelField() throws {
        var object = try jsonObject(ConvergenceDemo.make().project)
        object.removeValue(forKey: "logline")
        #expect(ProjectContract.missingFields(in: try data(object)) == ["logline"])
    }

    @Test("删掉卡片正文字段会带下标")
    func missingNodeField() throws {
        var object = try jsonObject(ConvergenceDemo.make().project)
        var nodes = try #require(object["nodes"] as? [[String: Any]])
        nodes[0].removeValue(forKey: "body")
        object["nodes"] = nodes
        #expect(ProjectContract.missingFields(in: try data(object)) == ["nodes[0].body"])
    }

    @Test("可空字段缺席不算缺")
    func optionalFieldsMayBeAbsent() throws {
        var object = try jsonObject(ConvergenceDemo.make().project)
        var nodes = try #require(object["nodes"] as? [[String: Any]])
        nodes[0].removeValue(forKey: "pov")
        nodes[0].removeValue(forKey: "targetWords")
        nodes[0].removeValue(forKey: "storyTimeLabel")
        object["nodes"] = nodes
        object.removeValue(forKey: "workingRouteEndingID")
        #expect(ProjectContract.missingFields(in: try data(object)).isEmpty)
    }

    @Test("v1 契约不要求 v2 才有的项目字段")
    func legacyVersionIgnoresV2Fields() throws {
        var object = try jsonObject(ConvergenceDemo.make().project)
        object["schemaVersion"] = 1
        object.removeValue(forKey: "cardGroupOverrides")
        #expect(ProjectContract.missingFields(in: try data(object)).isEmpty)
    }

    @Test("不是 JSON 对象时直接报根节点")
    func invalidRoot() {
        #expect(ProjectContract.missingFields(in: Data("[]".utf8)) == ["<root>"])
    }
}
