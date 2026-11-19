import Foundation
import Testing
@testable import CausalityCore

/// 第一轮验收：把两条路接到同一结局，保存并重开，大纲仍只出现一份结局正文。
@Suite("第一轮验收：两条路接到同一结局")
struct ConvergenceAcceptanceTests {
    @Test("保存重开后，结局正文只有一份，两条路的选择与原因都在")
    func twoRoutesToOneEnding() throws {
        let workspace = try TestWorkspace()
        defer { workspace.cleanup() }

        let script = ConvergenceDemo.make()
        let saved = try ProjectPackage.save(script.project, to: workspace.packageURL)
        #expect(saved.writtenAssetIDs.isEmpty)

        let loaded = try ProjectPackage.load(from: workspace.packageURL)
        #expect(loaded.project == script.project)

        let rows = OutlineBuilder.build(project: loaded.project).flatMap(\.rows)
        let endingRows = rows.filter { $0.nodeID == script.ending }
        #expect(endingRows.filter { $0.role == .scene }.count == 1)
        #expect(endingRows.filter { $0.role == .revisit }.count == 1)

        let labels = rows.compactMap(\.incoming?.label)
        #expect(labels.contains(script.keepSecretLabel))
        #expect(labels.contains(script.askTownsfolkLabel))
        #expect(labels.contains(script.causeLabel))

        // 两条路各自到达结局的说明都保留，且分属不同的边。
        let arrivals = rows.filter { $0.nodeID == script.ending }.compactMap(\.incoming)
        #expect(arrivals.count == 2)
        #expect(Set(arrivals.map(\.edgeID)).count == 2)
        #expect(Set(arrivals.map(\.kind)) == [.cause, .plain])
    }

    @Test("同一个结局在 Markdown 里也只展开一次")
    func markdownExpandsEndingOnce() throws {
        let script = ConvergenceDemo.make()
        let markdown = OutlineMarkdown.render(project: script.project)
        let headingCount = markdown.components(separatedBy: "### 旧渡口的信").count - 1
        #expect(headingCount == 1)
        #expect(markdown.contains("↪ 回到上文「旧渡口的信」"))
        #expect(markdown.contains(script.keepSecretLabel))
        #expect(markdown.contains(script.askTownsfolkLabel))
        #expect(markdown.contains("因为：\(script.causeLabel)"))
    }

    @Test("再改一条分支，另一条与结局都不受影响")
    func editingOneBranchKeepsTheOther() throws {
        var script = ConvergenceDemo.make()
        var project = script.project
        let keepSecretNode = project.node(script.keepSecret)!

        // 把"公开追问"改成"更含蓄的相遇"：改正文与出边文字，另一条分支原样保留。
        var operations = ProjectMutations.updateNode(script.askTownsfolk, in: project) { node in
            node.body = "卖纸的老人没有招呼，只把同纹的纸推到阿禾手边。"
        }
        operations += ProjectMutations.updateNode(script.ending, in: project) { node in
            node.summary = "两半信对上，众人一同去渡口。"
        }
        try ProjectEditing.apply(operations, to: &project)
        script.project = project

        let index = project.makeIndex()
        let outline = OutlineBuilder.build(project: project, index: index)[0]
        let sceneNodes = outline.rows
            .filter { $0.role == .scene }
            .compactMap { index.nodeByID[$0.nodeID] }
        #expect(sceneNodes.contains { $0.id == keepSecretNode.id && $0.body == keepSecretNode.body })
        #expect(outline.revisitCount == 1)
        #expect(outline.rows.compactMap(\.incoming?.label).contains(script.keepSecretLabel))
    }
}
