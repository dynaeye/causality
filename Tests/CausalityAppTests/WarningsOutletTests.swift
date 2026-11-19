import Foundation
import CausalityCore
import Testing
@testable import Causality

/// 工程提示的出口：校验问题、导入备注、配图未落盘都写进 `ProjectSession.warnings`，
/// 体检面板读它。这里钉住「打开就有、关掉一条只影响列表、重新体检再算一遍」。
@Suite("工程提示的出口")
@MainActor
struct WarningsOutletTests {
    /// 造一条确定会报的校验问题：一条连线的起点不存在。
    private func projectWithDanglingEdge() throws -> StoryProject {
        var project = StoryProject.empty(title: "提示")
        let node = StoryNode(title: "开头", isEntry: true)
        try ProjectEditing.apply(ProjectMutations.appendNode(node, to: project), to: &project)
        project.edges.append(StoryEdge(from: NodeID(), to: node.id))
        return project
    }

    @Test("打开工程带出提示，关掉一条、清空、重新体检都有对应行为")
    func warningsLifecycle() throws {
        let session = ProjectSession()
        let project = try projectWithDanglingEdge()
        session.open(project: project, at: nil)

        #expect(session.warnings == ProjectValidator.issues(in: project))
        #expect(session.warnings.count == 1)

        session.dismissWarning(at: 0)
        #expect(session.warnings.isEmpty)
        #expect(ProjectValidator.issues(in: project).count == 1, "关掉的是列表，工程本身的问题没有变")

        session.revalidateWarnings()
        #expect(session.warnings.count == 1)

        session.clearWarnings()
        #expect(session.warnings.isEmpty)

        session.dismissWarning(at: 3)
        #expect(session.warnings.isEmpty, "越界下标什么都不做")
    }

    @Test("没有工程时重新体检把提示清空")
    func revalidateWithoutProject() {
        let session = ProjectSession()
        session.warnings = ["旧提示"]
        session.revalidateWarnings()
        #expect(session.warnings.isEmpty)
    }
}
