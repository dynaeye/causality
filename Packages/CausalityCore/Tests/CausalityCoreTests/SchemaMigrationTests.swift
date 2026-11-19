import Foundation
import Testing
@testable import CausalityCore

@Suite("工程包版本迁移")
struct SchemaMigrationTests {
    private func makePackage(text: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-schema-\(UUID().uuidString)", isDirectory: true)
        let packageURL = root.appendingPathComponent("版本.\(ProjectPackage.fileExtension)", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try text.write(to: ProjectPackage.metadataURL(in: packageURL), atomically: true, encoding: .utf8)
        return packageURL
    }

    @Test("旧版本的工程包能读，并提示已升级")
    func upgradesOldPackage() throws {
        var project = StoryProject.empty(title: "旧包")
        project.schemaVersion = 0
        let data = try ProjectCoding.encode(project)
        var text = String(decoding: data, as: UTF8.self)
        text = text.replacingOccurrences(of: "\"schemaVersion\" : 0", with: "\"schemaVersion\" : 0")
        let packageURL = try makePackage(text: text)

        let loaded = try ProjectPackage.load(from: packageURL)
        #expect(loaded.project.title == "旧包")
        #expect(loaded.project.schemaVersion == StoryProject.currentSchemaVersion)
        #expect(loaded.warnings.contains { $0.contains("已按 v\(StoryProject.currentSchemaVersion) 读取并升级") })
    }

    @Test("保存时统一写当前版本")
    func savesCurrentVersion() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-schema-save-\(UUID().uuidString)", isDirectory: true)
        let packageURL = root.appendingPathComponent("新包.\(ProjectPackage.fileExtension)", isDirectory: true)
        var project = StoryProject.empty(title: "新包")
        project.schemaVersion = 0
        try ProjectPackage.save(project, to: packageURL)

        let reloaded = try ProjectPackage.load(from: packageURL)
        #expect(reloaded.project.schemaVersion == StoryProject.currentSchemaVersion)
        #expect(reloaded.warnings.contains { $0.contains("升级") } == false)
    }

    @Test("更高版本的包直接拒绝，错误信息可读")
    func rejectsNewerPackage() throws {
        var project = StoryProject.empty(title: "未来包")
        project.schemaVersion = StoryProject.currentSchemaVersion + 1
        let packageURL = try makePackage(text: String(decoding: try ProjectCoding.encode(project), as: UTF8.self))

        do {
            _ = try ProjectPackage.load(from: packageURL)
            Issue.record("更高版本应当拒绝")
        } catch let error as PackageError {
            #expect(error.description.contains("比当前 App 支持的"))
            #expect(error.localizedDescription.contains("更新 App"))
        }
    }

    @Test("meta 损坏时回退上一版本，两条路都留提示")
    func recoversFromPrevious() throws {
        let project = StoryProject.empty(title: "回退")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-recover-\(UUID().uuidString)", isDirectory: true)
        let packageURL = root.appendingPathComponent("回退.\(ProjectPackage.fileExtension)", isDirectory: true)
        try ProjectPackage.save(project, to: packageURL)

        // 再存一版，产生 previous；随后把 current 写坏。
        var changed = project
        changed.title = "回退-第二版"
        try ProjectPackage.save(changed, to: packageURL)
        try "{ 坏掉的 json".write(to: ProjectPackage.metadataURL(in: packageURL), atomically: true, encoding: .utf8)

        let loaded = try ProjectPackage.load(from: packageURL)
        #expect(loaded.recoveredFromPreviousVersion)
        #expect(loaded.warnings.contains { $0.contains("回退到上一版本") })
        #expect(loaded.project.title == "回退")
    }
}
