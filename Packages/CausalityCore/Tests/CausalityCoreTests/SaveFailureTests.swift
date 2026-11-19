import Foundation
import Testing
@testable import CausalityCore

@Suite("保存失败的恢复")
struct SaveFailureTests {
    private func packageURL(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-save-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("\(name).\(ProjectPackage.fileExtension)", isDirectory: true)
    }

    @Test("元数据写不进去时，回退点不会被毁掉")
    func metadataWriteFailureKeepsPrevious() throws {
        let url = try packageURL("写坏")
        let original = StoryProject.empty(title: "上一版")
        try ProjectPackage.save(original, to: url)

        // 再存一版，previous 里是「上一版」。
        var second = original
        second.title = "第二版"
        try ProjectPackage.save(second, to: url)

        // 把 project.json 换成目录，下一次写入必然失败。
        let metadata = ProjectPackage.metadataURL(in: url)
        try FileManager.default.removeItem(at: metadata)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)

        var third = second
        third.title = "第三版"
        #expect(throws: (any Error).self) {
            try ProjectPackage.save(third, to: url)
        }

        // 回退点仍是完整的「上一版」，而不是被搬过来的目录。
        let previous = try ProjectCoding.decode(Data(contentsOf: ProjectPackage.previousMetadataURL(in: url)))
        #expect(previous.title == "上一版")
    }

    @Test("配图写不进去时报错，元数据保持原样")
    func assetWriteFailureLeavesMetadata() throws {
        let url = try packageURL("配图")
        let original = StoryProject.empty(title: "有配图前")
        try ProjectPackage.save(original, to: url)
        let before = try Data(contentsOf: ProjectPackage.metadataURL(in: url))

        // assets 目录只读，图片写不进去。
        let assets = ProjectPackage.assetsDirectory(in: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: assets.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: assets.path)
        }

        var changed = original
        let asset = Asset(fileName: "cover.png", byteCount: 4, caption: "")
        changed.assets = [asset]
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        #expect(throws: (any Error).self) {
            try ProjectPackage.save(changed, to: url, newAssetData: [asset.id: data])
        }

        let after = try Data(contentsOf: ProjectPackage.metadataURL(in: url))
        #expect(before == after, "配图失败时元数据不该被改写")
    }

    @Test("缺配图数据时只记在报告里，元数据照常提交")
    func missingAssetDataIsReported() throws {
        let url = try packageURL("缺图")
        var project = StoryProject.empty(title: "缺图")
        let asset = Asset(fileName: "gone.png", byteCount: 10, caption: "")
        project.assets = [asset]

        let report = try ProjectPackage.save(project, to: url)
        #expect(report.missingAssetIDs == [asset.id])
        let loaded = try ProjectPackage.load(from: url)
        #expect(loaded.warnings.contains { $0.contains("配图文件缺失") })
    }
}
