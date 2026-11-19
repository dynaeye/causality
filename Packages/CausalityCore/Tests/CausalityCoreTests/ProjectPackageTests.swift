import Foundation
import Testing
@testable import CausalityCore

enum TestFailure: Error {
    case boom
}

struct TestWorkspace {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causality-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var packageURL: URL { root.appendingPathComponent("story.causal", isDirectory: true) }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

@Suite("工程包保存")
struct ProjectPackageTests {
    private func makeProjectWithImage() -> (project: StoryProject, assetID: AssetID, data: Data) {
        var script = ConvergenceDemo.make()
        var project = script.project
        let data = Data((0 ..< 4096).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        let asset = Asset(
            fileName: "river-lantern.png",
            sha256: Digest.sha256Hex(data),
            byteCount: data.count,
            pixelWidth: 4096,
            pixelHeight: 4096,
            caption: "夜河上的河灯"
        )
        var operations = ProjectMutations.appendAsset(asset, to: project)
        operations += ProjectMutations.attachCover(asset.id, to: script.lantern, in: project)
        try? ProjectEditing.apply(operations, to: &project)
        script.project = project
        return (project, asset.id, data)
    }

    @Test("保存后重新打开，内容逐字段一致")
    func roundTrip() throws {
        let workspace = try TestWorkspace()
        defer { workspace.cleanup() }

        let (project, _, _) = makeProjectWithImage()
        try ProjectPackage.save(project, to: workspace.packageURL)
        let loaded = try ProjectPackage.load(from: workspace.packageURL)

        #expect(loaded.project == project)
        #expect(loaded.warnings.contains { $0.contains("配图文件缺失") })
        #expect(!loaded.recoveredFromPreviousVersion)
    }

    @Test("改一句台词时原图零写入")
    func textEditDoesNotRewriteImages() throws {
        let workspace = try TestWorkspace()
        defer { workspace.cleanup() }

        let (project, assetID, data) = makeProjectWithImage()
        let script = ConvergenceDemo.make()

        let first = try ProjectPackage.save(project, to: workspace.packageURL, newAssetData: [assetID: data])
        #expect(first.writtenAssetIDs == [assetID])
        #expect(first.reusedAssetIDs.isEmpty)

        let assetURL = ProjectPackage.assetURL(for: project.assets[0], in: workspace.packageURL)
        let before = try FileManager.default.attributesOfItem(atPath: assetURL.path)[.modificationDate] as? Date

        let edits = ProjectMutations.updateNode(script.ending, in: project) { node in
            node.body += "这句话是新写的。"
        }
        var edited = project
        try ProjectEditing.apply(edits, to: &edited)

        let second = try ProjectPackage.save(edited, to: workspace.packageURL)
        let after = try FileManager.default.attributesOfItem(atPath: assetURL.path)[.modificationDate] as? Date

        #expect(second.writtenAssetIDs.isEmpty)
        #expect(second.reusedAssetIDs == [assetID])
        #expect(before == after)
        let reopenedBody = try ProjectPackage.load(from: workspace.packageURL).project.node(script.ending)?.body
        #expect(reopenedBody?.hasSuffix("这句话是新写的。") == true)
    }

    @Test("写到一半退出：重开仍读到上一版完整内容与配图")
    func interruptedSaveKeepsPreviousVersion() throws {
        let workspace = try TestWorkspace()
        defer { workspace.cleanup() }

        let (project, assetID, data) = makeProjectWithImage()
        let script = ConvergenceDemo.make()
        try ProjectPackage.save(project, to: workspace.packageURL, newAssetData: [assetID: data])

        // 第二版：改正文、加一张新图，但元数据提交前模拟退出。
        var second = project
        let edits = ProjectMutations.updateNode(script.ending, in: second) { node in
            node.body = "这一版不该被读到。"
        }
        try ProjectEditing.apply(edits, to: &second)
        let extra = Data(repeating: 0x2A, count: 1024)
        let extraAsset = Asset(fileName: "extra.png", sha256: Digest.sha256Hex(extra), byteCount: extra.count)
        try ProjectEditing.apply(ProjectMutations.appendAsset(extraAsset, to: second), to: &second)

        var didFail = false
        do {
            _ = try ProjectPackage.save(
                second,
                to: workspace.packageURL,
                newAssetData: [extraAsset.id: extra],
                hooks: SaveHooks(beforeMetadataCommit: { throw TestFailure.boom })
            )
        } catch {
            didFail = true
        }
        #expect(didFail)

        let reopened = try ProjectPackage.load(from: workspace.packageURL)
        #expect(reopened.project.node(script.ending)?.body.contains("这一版不该被读到") == false)
        #expect(reopened.project == project)
        let assetURL = ProjectPackage.assetURL(for: project.assets[0], in: workspace.packageURL)
        #expect(FileManager.default.fileExists(atPath: assetURL.path))
        let writtenBack = try Data(contentsOf: assetURL)
        #expect(writtenBack == data)
    }

    @Test("元数据损坏时回退到上一版本")
    func corruptedMetadataFallsBack() throws {
        let workspace = try TestWorkspace()
        defer { workspace.cleanup() }

        let (project, _, _) = makeProjectWithImage()
        try ProjectPackage.save(project, to: workspace.packageURL)
        var second = project
        try ProjectEditing.apply(
            ProjectMutations.updateHeader(logline: "第二版梗概", in: second),
            to: &second
        )
        try ProjectPackage.save(second, to: workspace.packageURL)

        let metadataURL = ProjectPackage.metadataURL(in: workspace.packageURL)
        try Data("{ 这不是 JSON".utf8).write(to: metadataURL)

        let loaded = try ProjectPackage.load(from: workspace.packageURL)
        #expect(loaded.recoveredFromPreviousVersion)
        #expect(loaded.project == project)
    }

    @Test("保存后清掉不再引用的图片文件")
    func orphanAssetsArePruned() throws {
        let workspace = try TestWorkspace()
        defer { workspace.cleanup() }

        let (project, assetID, data) = makeProjectWithImage()
        try ProjectPackage.save(project, to: workspace.packageURL, newAssetData: [assetID: data])

        let strayURL = ProjectPackage.assetsDirectory(in: workspace.packageURL)
            .appendingPathComponent("stray.png")
        try Data(repeating: 0x01, count: 8).write(to: strayURL)

        var second = project
        try ProjectEditing.apply(
            ProjectMutations.updateHeader(logline: "触发一次保存", in: second),
            to: &second
        )
        let report = try ProjectPackage.save(second, to: workspace.packageURL)
        #expect(report.prunedAssetFileNames == ["stray.png"])
        #expect(!FileManager.default.fileExists(atPath: strayURL.path))
    }

    @Test("包不存在时给出明确错误")
    func loadingMissingPackageFails() throws {
        let workspace = try TestWorkspace()
        defer { workspace.cleanup() }

        var caught: PackageError?
        do {
            _ = try ProjectPackage.load(from: workspace.packageURL)
        } catch let error as PackageError {
            caught = error
        }
        #expect(caught == .notAPackage(workspace.packageURL.path))
    }
}

@Suite("旧工程包兼容")
struct ProjectCompatibilityTests {
    @Test("缺少新字段的旧 JSON 仍能打开")
    func decodeOlderPackage() throws {
        let json = """
        {"schemaVersion":1,"title":"旧项目","revision":2,
         "chapters":[],"nodes":[],"edges":[],"characters":[],"places":[],
         "settings":[],"assets":[],"discussions":[],"canvas":{}}
        """
        let project = try ProjectCoding.decode(Data(json.utf8))
        #expect(project.title == "旧项目")
        #expect(project.characterCanvas.isEmpty)
        #expect(project.logline.isEmpty)
    }

    @Test("人物坐标随工程保存并读回")
    func characterCanvasRoundTrip() throws {
        var demo = ConvergenceDemo.make()
        var project = demo.project
        let character = try #require(project.characters.first)
        try ProjectEditing.apply(
            ProjectMutations.setCharacterCanvasPoint(CanvasPoint(x: 120, y: 80), for: character.id, in: project),
            to: &project
        )
        demo.project = project

        let workspace = try TestWorkspace()
        defer { workspace.cleanup() }
        try ProjectPackage.save(project, to: workspace.packageURL)
        let loaded = try ProjectPackage.load(from: workspace.packageURL)
        #expect(loaded.project.characterCanvas[character.id] == CanvasPoint(x: 120, y: 80))
        #expect(loaded.project == project)
    }
}

@Suite("并发保存指纹")
struct PackageStampTests {
    @Test("指纹匹配时正常保存，过期时拒绝覆盖")
    func staleStampConflicts() throws {
        let workspace = try TestWorkspace()
        defer { workspace.cleanup() }

        var project = ConvergenceDemo.make().project
        try ProjectPackage.save(project, to: workspace.packageURL)
        let opened = try #require(ProjectPackage.stamp(in: workspace.packageURL))

        project.title = "第一次改"
        project.revision += 1
        project.modifiedAt = Date()
        try ProjectPackage.save(project, to: workspace.packageURL, expecting: opened)

        // 另一个进程先写了一次，打开时的指纹就过期了。
        var external = project
        external.title = "别的程序改的"
        external.revision += 1
        external.modifiedAt = Date()
        try ProjectPackage.save(external, to: workspace.packageURL, expecting: ProjectPackage.stamp(in: workspace.packageURL))

        var local = project
        local.title = "本机改的"
        local.revision += 1
        local.modifiedAt = Date()
        #expect(throws: PackageError.self) {
            try ProjectPackage.save(local, to: workspace.packageURL, expecting: opened)
        }
        let disk = try ProjectPackage.load(from: workspace.packageURL).project
        #expect(disk.title == "别的程序改的")
    }

    @Test("另存为新包不需要指纹")
    func newPackageNeedsNoStamp() throws {
        let workspace = try TestWorkspace()
        defer { workspace.cleanup() }
        let project = ConvergenceDemo.make().project
        try ProjectPackage.save(project, to: workspace.packageURL)
        #expect(ProjectPackage.stamp(in: workspace.packageURL) != nil)
    }
}

@Suite("文件指纹兜底")
struct PackageStampMTimesTests {
    @Test("revision 不变、文件 mtime 变了也报冲突")
    func mtimeChangesConflict() throws {
        let workspace = try TestWorkspace()
        defer { workspace.cleanup() }
        var project = ConvergenceDemo.make().project
        try ProjectPackage.save(project, to: workspace.packageURL)
        let opened = try #require(ProjectPackage.stamp(in: workspace.packageURL))

        // 外部进程只加了一章，revision / modifiedAt 都不动。
        var external = project
        try ProjectEditing.apply(
            ProjectMutations.appendChapter(Chapter(title: "外部章"), to: external),
            to: &external
        )
        try ProjectPackage.save(external, to: workspace.packageURL)
        let after = try #require(ProjectPackage.stamp(in: workspace.packageURL))
        #expect(after.fileModifiedAt != opened.fileModifiedAt || after.revision != opened.revision)

        var local = project
        local.title = "本机"
        #expect(throws: PackageError.self) {
            try ProjectPackage.save(local, to: workspace.packageURL, expecting: opened)
        }
    }
}
