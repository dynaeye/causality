import Foundation
import Testing
@testable import CausalityCore

@Suite("孤儿配图进回收站")
struct AssetTrashTests {
    private func package() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-trash-\(UUID().uuidString)", isDirectory: true)
        let url = root.appendingPathComponent("图.\(ProjectPackage.fileExtension)", isDirectory: true)
        var project = StoryProject.empty(title: "图")
        try ProjectPackage.save(project, to: url)
        return url
    }

    @Test("不再引用的配图搬进 .trash，而不是删掉")
    func orphanMovesToTrash() throws {
        let url = try package()
        let assets = ProjectPackage.assetsDirectory(in: url)
        let orphan = assets.appendingPathComponent("old.png")
        try Data([0x89, 0x50]).write(to: orphan)

        // 保存一次，孤儿文件应当离开 assets 根目录
        try ProjectPackage.save(StoryProject.empty(title: "图"), to: url)

        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        let trash = assets.appendingPathComponent(ProjectPackage.trashDirectoryName)
        let stamps = try FileManager.default.contentsOfDirectory(atPath: trash.path)
        #expect(stamps.count == 1)
        let moved = trash.appendingPathComponent(stamps[0]).appendingPathComponent("old.png")
        #expect(FileManager.default.fileExists(atPath: moved.path))
    }

    @Test("超过保留期的回收站目录会被清掉")
    func purgeOldTrash() throws {
        let url = try package()
        let trash = ProjectPackage.assetsDirectory(in: url)
            .appendingPathComponent(ProjectPackage.trashDirectoryName)
            .appendingPathComponent("20200101-000000")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data([1]).write(to: trash.appendingPathComponent("x.png"))
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-30 * 86_400)],
            ofItemAtPath: trash.path
        )

        let purged = ProjectPackage.purgeAssetTrash(in: url, olderThan: 7)
        #expect(purged == 1)
        #expect(!FileManager.default.fileExists(atPath: trash.path))
    }
}
