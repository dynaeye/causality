import Foundation
import Testing
@testable import CausalityCore

@Suite("另存为：配图一起走")
struct SaveAsAssetTests {
    private func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-saveas-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// 一个带配图的工程包。
    private func makePackage(in root: URL, title: String) throws -> (url: URL, project: StoryProject, asset: Asset, data: Data) {
        var project = StoryProject.empty(title: title)
        let node = StoryNode(title: "河灯", isEntry: true)
        try ProjectEditing.apply(ProjectMutations.appendNode(node, to: project), to: &project)

        let data = Data((0 ..< 2048).map { UInt8(truncatingIfNeeded: $0 &* 11) })
        let asset = Asset(
            fileName: "lantern.png",
            sha256: Digest.sha256Hex(data),
            byteCount: data.count,
            pixelWidth: 512,
            pixelHeight: 512,
            caption: "河灯"
        )
        var operations = ProjectMutations.appendAsset(asset, to: project)
        operations += ProjectMutations.attachCover(asset.id, to: node.id, in: project)
        try ProjectEditing.apply(operations, to: &project)

        let url = root.appendingPathComponent("\(title).\(ProjectPackage.fileExtension)", isDirectory: true)
        try ProjectPackage.save(project, to: url, newAssetData: [asset.id: data])
        return (url, project, asset, data)
    }

    @Test("另存为新包时，原包里已有的配图会复制过去")
    func saveAsCopiesExistingAssets() throws {
        let root = try workspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try makePackage(in: root, title: "原包")
        var edited = source.project
        edited.title = "另存为"
        let destination = root.appendingPathComponent("另存为.\(ProjectPackage.fileExtension)", isDirectory: true)

        let report = try ProjectPackage.save(
            edited,
            to: destination,
            copyingAssetsFrom: source.url
        )

        #expect(report.copiedAssetIDs == [source.asset.id])
        #expect(report.missingAssetIDs.isEmpty)
        let copied = ProjectPackage.assetURL(for: source.asset, in: destination)
        #expect(FileManager.default.fileExists(atPath: copied.path))
        #expect(try Data(contentsOf: copied) == source.data)

        // 新包自己带图，重新打开时不该报缺图。
        let loaded = try ProjectPackage.load(from: destination)
        #expect(!loaded.warnings.contains { $0.contains("配图文件缺失") })
        #expect(loaded.project.title == edited.title)
        #expect(loaded.project.nodes.map(\.title) == edited.nodes.map(\.title))
        #expect(loaded.project.assets.map(\.fileName) == edited.assets.map(\.fileName))
    }

    @Test("恢复草稿：内存里的新图与原包里的旧图一起写进去")
    func draftRecoveryWritesBothImageSources() throws {
        let root = try workspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try makePackage(in: root, title: "冲突中")
        var extended = source.project
        let freshData = Data((0 ..< 1024).map { UInt8(truncatingIfNeeded: $0 &* 3) })
        let fresh = Asset(
            fileName: "fresh.png",
            sha256: Digest.sha256Hex(freshData),
            byteCount: freshData.count,
            pixelWidth: 400,
            pixelHeight: 300,
            caption: "刚贴进来的"
        )
        try ProjectEditing.apply(ProjectMutations.appendAsset(fresh, to: extended), to: &extended)

        let draft = root.appendingPathComponent("恢复草稿.\(ProjectPackage.fileExtension)", isDirectory: true)
        let report = try ProjectPackage.save(
            extended,
            to: draft,
            newAssetData: [fresh.id: freshData],
            copyingAssetsFrom: source.url
        )

        #expect(report.writtenAssetIDs == [fresh.id])
        #expect(report.copiedAssetIDs == [source.asset.id])
        #expect(report.missingAssetIDs.isEmpty)
        #expect(try Data(contentsOf: ProjectPackage.assetURL(for: fresh, in: draft)) == freshData)
        #expect(try Data(contentsOf: ProjectPackage.assetURL(for: source.asset, in: draft)) == source.data)
        #expect(!(try ProjectPackage.load(from: draft).warnings.contains { $0.contains("配图文件缺失") }))
    }

    @Test("原包也缺那张图时，报告里说清楚，元数据照常写")
    func saveAsReportsMissingSourceAsset() throws {
        let root = try workspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try makePackage(in: root, title: "缺图")
        try FileManager.default.removeItem(at: ProjectPackage.assetURL(for: source.asset, in: source.url))
        let destination = root.appendingPathComponent("再存.\(ProjectPackage.fileExtension)", isDirectory: true)

        let report = try ProjectPackage.save(source.project, to: destination, copyingAssetsFrom: source.url)

        #expect(report.copiedAssetIDs.isEmpty)
        #expect(report.missingAssetIDs == [source.asset.id])
        #expect(try ProjectPackage.load(from: destination).warnings.contains { $0.contains("配图文件缺失") })
    }
}

@Suite("整包替换")
struct PackageReplaceTests {
    private func package(in root: URL, name: String, title: String) throws -> URL {
        let url = root.appendingPathComponent("\(name).\(ProjectPackage.fileExtension)", isDirectory: true)
        try ProjectPackage.save(StoryProject.empty(title: title), to: url)
        return url
    }

    @Test("替换成功后，路径上是新包")
    func replacesInPlace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-replace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let target = try package(in: root, name: "目标", title: "旧包")
        let staged = try package(in: root, name: "暂存", title: "新包")

        try ProjectPackage.replacePackage(at: target, with: staged)

        #expect(try ProjectPackage.load(from: target).project.title == "新包")
        #expect(!FileManager.default.fileExists(atPath: staged.path), "换过去之后暂存包不该留在原地")
    }

    @Test("替换失败时旧包原样放回")
    func restoresTargetOnFailure() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-replace-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let target = try package(in: root, name: "目标", title: "旧包")
        let missing = root.appendingPathComponent("没写出来.\(ProjectPackage.fileExtension)", isDirectory: true)

        #expect(throws: (any Error).self) {
            try ProjectPackage.replacePackage(at: target, with: missing)
        }

        #expect(try ProjectPackage.load(from: target).project.title == "旧包")
    }

    @Test("目标还不存在时直接把完整包搬过去")
    func movesWhenTargetIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-replace-new-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let staged = try package(in: root, name: "草稿", title: "刚写的")
        let destination = root.appendingPathComponent("正式.\(ProjectPackage.fileExtension)", isDirectory: true)

        try ProjectPackage.replacePackage(at: destination, with: staged)

        #expect(try ProjectPackage.load(from: destination).project.title == "刚写的")
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }
}
