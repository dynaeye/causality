import Foundation
import Testing
@testable import CausalityCore

@Suite("Markdown 导出带上配图")
struct MarkdownExportTests {
    private func makeProject() throws -> (project: StoryProject, asset: Asset, data: Data) {
        var script = ConvergenceDemo.make()
        var project = script.project
        let data = Data((0 ..< 3072).map { UInt8(truncatingIfNeeded: $0 &* 13) })
        let asset = Asset(
            fileName: "river-lantern.png",
            sha256: Digest.sha256Hex(data),
            byteCount: data.count,
            pixelWidth: 640,
            pixelHeight: 480,
            caption: "夜河上的河灯"
        )
        var operations = ProjectMutations.appendAsset(asset, to: project)
        operations += ProjectMutations.attachCover(asset.id, to: script.lantern, in: project)
        try ProjectEditing.apply(operations, to: &project)
        script.project = project
        return (project, asset, data)
    }

    @Test("Markdown 用相对路径引用配图，图片复制到同级 assets/")
    func exportCarriesImages() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-md-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let (project, asset, imageData) = try makeProject()
        let package = root.appendingPathComponent("工程.\(ProjectPackage.fileExtension)", isDirectory: true)
        try ProjectPackage.save(project, to: package, newAssetData: [asset.id: imageData])

        let exportFolder = root.appendingPathComponent("导出", isDirectory: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        let markdownURL = exportFolder.appendingPathComponent("大纲.md")

        let report = try MarkdownExport.write(project: project, packageURL: package, to: markdownURL)

        #expect(report.missingAssetFileNames.isEmpty)
        #expect(report.copiedAssetFileNames == [asset.fileName])
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        #expect(markdown.contains("![夜河上的河灯](assets/\(asset.fileName))"))

        let exportedImage = report.assetsDirectory.appendingPathComponent(asset.fileName)
        #expect(try Data(contentsOf: exportedImage) == imageData)

        // 把原工程包移走：导出物自己带图，引用仍然落得下来。
        try FileManager.default.removeItem(at: package)
        let reopened = try String(contentsOf: markdownURL, encoding: .utf8)
        #expect(reopened.contains("](assets/\(asset.fileName))"))
        #expect(FileManager.default.fileExists(atPath: exportedImage.path))
    }

    @Test("工程里缺图时照实报告，Markdown 仍然写出")
    func missingAssetIsReported() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-md-missing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let (project, asset, imageData) = try makeProject()
        let package = root.appendingPathComponent("工程.\(ProjectPackage.fileExtension)", isDirectory: true)
        try ProjectPackage.save(project, to: package, newAssetData: [asset.id: imageData])
        try FileManager.default.removeItem(at: ProjectPackage.assetURL(for: asset, in: package))

        let markdownURL = root.appendingPathComponent("大纲.md")
        let report = try MarkdownExport.write(project: project, packageURL: package, to: markdownURL)

        #expect(report.missingAssetFileNames == [asset.fileName])
        #expect(report.copiedAssetFileNames.isEmpty)
        #expect(try String(contentsOf: markdownURL, encoding: .utf8).contains("](assets/\(asset.fileName))"))
    }

    @Test("只导出某条路线时，只带这条路用到的图")
    func routeExportCopiesOnlyRouteImages() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-md-route-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let (project, asset, imageData) = try makeProject()
        let package = root.appendingPathComponent("工程.\(ProjectPackage.fileExtension)", isDirectory: true)
        try ProjectPackage.save(project, to: package, newAssetData: [asset.id: imageData])

        // 先算好这条路线，再去一张不在路上的卡上挂图。
        guard let ending = project.nodes.first(where: { $0.kind == .ending }) else {
            Issue.record("示例工程没有结局")
            return
        }
        let route = StoryRoute.paths(to: ending.id, in: project)
        guard let offRoute = project.nodes.first(where: { !route.nodeIDs.contains($0.id) }) else {
            Issue.record("示例工程里每张卡都在通往结局的路上")
            return
        }

        var extended = project
        let otherData = Data(repeating: 0x5A, count: 128)
        let other = Asset(fileName: "unused.png", sha256: Digest.sha256Hex(otherData), byteCount: otherData.count)
        var operations = ProjectMutations.appendAsset(other, to: extended)
        operations += ProjectMutations.attachCover(other.id, to: offRoute.id, in: extended)
        try ProjectEditing.apply(operations, to: &extended)
        try ProjectPackage.save(extended, to: package, newAssetData: [other.id: otherData])

        let markdownURL = root.appendingPathComponent("路线.md")
        let report = try MarkdownExport.write(
            project: extended,
            route: route,
            packageURL: package,
            to: markdownURL
        )

        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        for fileName in report.copiedAssetFileNames {
            #expect(markdown.contains("](assets/\(fileName))"))
        }
        #expect(!report.copiedAssetFileNames.contains(other.fileName))
    }
}
