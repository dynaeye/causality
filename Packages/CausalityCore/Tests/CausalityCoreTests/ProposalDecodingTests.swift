import Foundation
import Testing
@testable import CausalityCore

@Suite("提案解码容错")
struct ProposalDecodingTests {
    @Test("模型漏写 ref、用 id 与 text 也能读进来")
    func lenientNodeFields() throws {
        let json = """
        {"summary":"补一句","nodes":[
          {"id":"n_ferry","title":"旧渡口","kind":"event","summary":"","text":"她把信折好。",
           "characterNames":["阿禾"],"placeNames":[],"settingTitles":[]}
        ],"edges":[],"changes":[],"removals":[],"notes":[]}
        """
        let payload = try ProposalParsing.decodePayload(from: json)
        #expect(payload.nodes.count == 1)
        #expect(payload.nodes[0].ref == "n_ferry")
        #expect(payload.nodes[0].body == "她把信折好。")
        #expect(payload.nodes[0].characterNames == ["阿禾"])
    }

    @Test("用 field/before/after 描述改动时映射到对应字段")
    func lenientChangeShape() throws {
        let json = """
        {"summary":"","nodes":[],"edges":[],
         "changes":[{"target":"node","id":"3FE157CA-470B-40D8-A534-9D01B06FE3EF",
                     "field":"body","before":"旧句","after":"新句"}],
         "removals":[],"notes":[]}
        """
        let payload = try ProposalParsing.decodePayload(from: json)
        #expect(payload.changes.count == 1)
        #expect(payload.changes[0].body == "新句")
    }

    @Test("缺少数组与未知枚举不致命")
    func lenientEnumsAndMissingArrays() throws {
        let json = """
        {"summary":"x","nodes":[{"ref":"a","title":"一","kind":"scene"}],
         "edges":[{"from":"a","to":"b","kind":"casual"}],"changes":[]}
        """
        let payload = try ProposalParsing.decodePayload(from: json)
        #expect(payload.nodes[0].kind == .event)
        #expect(payload.edges[0].kind == .plain)
        #expect(payload.removals.isEmpty)
        #expect(payload.notes.isEmpty)
    }
}
