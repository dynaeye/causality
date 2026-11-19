import Foundation
import Testing
@testable import CausalityCore

@Suite("工程包历史快照")
struct ProjectHistoryTests {
    private func makePackage(title: String) throws -> (URL, StoryProject) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-history-\(UUID().uuidString)", isDirectory: true)
        let packageURL = root.appendingPathComponent("测试.\(ProjectPackage.fileExtension)", isDirectory: true)
        let project = StoryProject.empty(title: title)
        try ProjectPackage.save(project, to: packageURL)
        return (packageURL, project)
    }

    @Test("改动前留快照，undo 把内容写回")
    func snapshotAndUndo() throws {
        let (packageURL, original) = try makePackage(title: "第一版")

        // 改一次并保存，改动前留快照
        try ProjectHistory.snapshotCurrent(in: packageURL)
        var changed = original
        changed.title = "第二版"
        changed.revision += 1
        try ProjectPackage.save(changed, to: packageURL)
        #expect(try ProjectPackage.load(from: packageURL).project.title == "第二版")

        let entries = try ProjectHistory.list(in: packageURL)
        #expect(entries.count == 1)

        let restored = try ProjectHistory.undo(steps: 1, in: packageURL)
        #expect(restored.count == 1)
        #expect(try ProjectPackage.load(from: packageURL).project.title == "第一版")
        #expect(try ProjectHistory.list(in: packageURL).isEmpty)
    }

    @Test("多步撤回按时间倒序，撤回后快照被消耗")
    func multipleSteps() throws {
        let (packageURL, original) = try makePackage(title: "v1")

        for step in 2...4 {
            try ProjectHistory.snapshotCurrent(in: packageURL)
            var next = try ProjectPackage.load(from: packageURL).project
            next.title = "v\(step)"
            next.revision += 1
            try ProjectPackage.save(next, to: packageURL)
        }
        #expect(try ProjectHistory.list(in: packageURL).count == 3)

        let restored = try ProjectHistory.undo(steps: 2, in: packageURL)
        #expect(restored.count == 2)
        #expect(try ProjectPackage.load(from: packageURL).project.title == "v2")
        #expect(try ProjectHistory.list(in: packageURL).count == 1)
        #expect(original.title == "v1")
    }

    @Test("内容没变时不重复存快照")
    func skipsIdenticalSnapshots() throws {
        let (packageURL, _) = try makePackage(title: "同一版")
        try ProjectHistory.snapshotCurrent(in: packageURL)
        _ = try ProjectHistory.snapshotCurrent(in: packageURL)
        #expect(try ProjectHistory.list(in: packageURL).count == 1)
    }

    @Test("超出上限时丢最旧的")
    func prunes() throws {
        let (packageURL, _) = try makePackage(title: "起点")
        for step in 1...(ProjectHistory.limit + 3) {
            try ProjectHistory.snapshotCurrent(in: packageURL)
            var next = try ProjectPackage.load(from: packageURL).project
            next.title = "第 \(step) 次"
            next.revision += 1
            try ProjectPackage.save(next, to: packageURL)
        }
        #expect(try ProjectHistory.list(in: packageURL).count <= ProjectHistory.limit)
    }

    @Test("没有工程包时列表为空，而不是报错")
    func emptyWhenNoSnapshots() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-empty-\(UUID().uuidString)", isDirectory: true)
        #expect(try ProjectHistory.list(in: root).isEmpty)
        #expect(try ProjectHistory.latest(in: root) == nil)
    }
}

@Suite("历史 redo")
struct ProjectHistoryRedoTests {
    private func makePackage() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-redo-\(UUID().uuidString)", isDirectory: true)
        let packageURL = root.appendingPathComponent("测试.causal", isDirectory: true)
        try ProjectPackage.save(StoryProject.empty(title: "v1"), to: packageURL)
        for step in 2...4 {
            try ProjectHistory.snapshotCurrent(in: packageURL)
            var next = try ProjectPackage.load(from: packageURL).project
            next.title = "v\(step)"
            next.revision += 1
            try ProjectPackage.save(next, to: packageURL)
        }
        return packageURL
    }

    @Test("undo 三步再 redo 三步回到原位")
    func redoThreeSteps() throws {
        let packageURL = try makePackage()
        try ProjectHistory.undo(steps: 3, in: packageURL)
        #expect(try ProjectPackage.load(from: packageURL).project.title == "v1")
        #expect(try ProjectHistory.redoList(in: packageURL).count == 3)

        let redone = try ProjectHistory.redo(steps: 3, in: packageURL)
        #expect(redone.count == 3)
        #expect(try ProjectPackage.load(from: packageURL).project.title == "v4")
        #expect(try ProjectHistory.redoList(in: packageURL).isEmpty)
        #expect(try ProjectHistory.list(in: packageURL).count >= 3)
    }

    @Test("撤回后新改动会清空 redo")
    func newEditClearsRedo() throws {
        let packageURL = try makePackage()
        try ProjectHistory.undo(steps: 1, in: packageURL)
        #expect(try ProjectHistory.redoList(in: packageURL).count == 1)

        try ProjectHistory.snapshotCurrent(in: packageURL)
        var next = try ProjectPackage.load(from: packageURL).project
        next.title = "新改动"
        next.revision += 1
        try ProjectPackage.save(next, to: packageURL)
        #expect(try ProjectHistory.redoList(in: packageURL).isEmpty)
        let redone = try ProjectHistory.redo(steps: 1, in: packageURL)
        #expect(redone.isEmpty)
    }
}
