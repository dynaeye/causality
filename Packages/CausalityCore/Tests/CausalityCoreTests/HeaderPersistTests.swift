import Foundation
import Testing
@testable import CausalityCore

@Suite("改项目名要落盘")
struct HeaderPersistTests {
    @Test("updateHeader 之后保存再读，标题是新的")
    func persists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-header-\(UUID().uuidString)", isDirectory: true)
        let url = root.appendingPathComponent("标题.\(ProjectPackage.fileExtension)", isDirectory: true)

        var project = StoryProject.empty(title: "旧标题")
        try ProjectPackage.save(project, to: url)
        try ProjectEditing.apply(
            ProjectMutations.updateHeader(title: "搬运测试", in: project),
            to: &project
        )
        #expect(project.title == "搬运测试")
        try ProjectPackage.save(project, to: url)

        let loaded = try ProjectPackage.load(from: url).project
        #expect(loaded.title == "搬运测试")
    }

    @Test("空标题被忽略，保持原名")
    func ignoresEmpty() throws {
        var project = StoryProject.empty(title: "原名")
        let operations = ProjectMutations.updateHeader(title: "   ", in: project)
        try ProjectEditing.apply(operations, to: &project)
        #expect(project.title == "   ")
    }
}
