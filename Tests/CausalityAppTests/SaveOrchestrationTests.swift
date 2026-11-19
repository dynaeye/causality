import Foundation
import CausalityCore
import Testing
@testable import Causality

/// 写盘闸门：让第一次写盘停在闸门里，测试在停住时补一句话，再放行。
///
/// 顺序由两个同步点钉住：`waitUntilPaused()` 等到写盘真的进来，`release()` 放行。
actor WriteGate {
    private var isOpen = false
    private var didPause = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    /// 挂在 SaveQueue 上：第一次写盘停住，之后的写直接放行。
    func pause() async {
        guard !isOpen else { return }
        didPause = true
        for waiter in pauseWaiters {
            waiter.resume()
        }
        pauseWaiters.removeAll()
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    /// 等到写盘已经停在闸门里。
    func waitUntilPaused() async {
        if didPause { return }
        await withCheckedContinuation { continuation in
            pauseWaiters.append(continuation)
        }
    }

    /// 放行写盘；之后的写盘不再停。
    func release() {
        isOpen = true
        for waiter in releaseWaiters {
            waiter.resume()
        }
        releaseWaiters.removeAll()
    }
}

@Suite("保存编排：写盘期间补的一句话")
@MainActor
struct SaveOrchestrationTests {
    private static let recentsKey = "causal.recentProjects"

    private struct Fixture {
        var session: ProjectSession
        var gate: WriteGate
        var url: URL
        var nodeID: NodeID
        var root: URL
    }

    private func makeFixture() async throws -> Fixture {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("causal-save-orchestration-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("工程.\(ProjectPackage.fileExtension)", isDirectory: true)

        var project = StoryProject.empty(title: "版本核对")
        let node = StoryNode(title: "开头", isEntry: true)
        try ProjectEditing.apply(ProjectMutations.appendNode(node, to: project), to: &project)
        try ProjectPackage.save(project, to: url)

        let gate = WriteGate()
        let queue = SaveQueue()
        await queue.setBeforeSave { await gate.pause() }
        let session = ProjectSession(saveQueue: queue)
        session.open(project: project, at: url)
        return Fixture(session: session, gate: gate, url: url, nodeID: node.id, root: root)
    }

    private func withRecentsRestored<T: Sendable>(_ body: () async throws -> T) async rethrows -> T {
        let defaults = UserDefaults.standard
        let saved = defaults.stringArray(forKey: Self.recentsKey)
        defer {
            if let saved {
                defaults.set(saved, forKey: Self.recentsKey)
            } else {
                defaults.removeObject(forKey: Self.recentsKey)
            }
        }
        return try await body()
    }

    @Test("⌘S 写盘期间补的一句，保存成功时已经在盘上", .timeLimit(.minutes(1)))
    func manualSaveCatchesTextTypedDuringWrite() async throws {
        try await withRecentsRestored {
            let fixture = try await makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }

            let saveTask = Task { await fixture.session.save() }
            await fixture.gate.waitUntilPaused()

            // 写盘已经停住，作者继续输入；400ms 防抖还没到，这句话只在草稿里。
            fixture.session.stageTextDraft("写盘期间补的最后一句。", for: .nodeBody(fixture.nodeID))
            #expect(fixture.session.project?.node(fixture.nodeID)?.body == "", "这句话此刻还在防抖里")

            await fixture.gate.release()
            let outcome = await saveTask.value
            #expect(outcome.isSaved)
            #expect(fixture.session.editRevision == fixture.session.savedRevision)

            let disk = try ProjectPackage.load(from: try #require(fixture.session.packageURL)).project
            #expect(disk.node(fixture.nodeID)?.body.contains("写盘期间补的最后一句。") == true)
        }
    }

    @Test("写盘期间补的一句，切换工程前也会补写进旧包", .timeLimit(.minutes(1)))
    func switchingCatchesTextTypedDuringWrite() async throws {
        try await withRecentsRestored {
            let fixture = try await makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }

            let switchTask = Task { await fixture.session.saveBeforeSwitching() }
            await fixture.gate.waitUntilPaused()

            fixture.session.stageTextDraft("切换前的最后一句。", for: .nodeBody(fixture.nodeID))
            #expect(fixture.session.project?.node(fixture.nodeID)?.body == "")

            await fixture.gate.release()
            let canSwitch = await switchTask.value
            #expect(canSwitch)

            let disk = try ProjectPackage.load(from: try #require(fixture.session.packageURL)).project
            #expect(disk.node(fixture.nodeID)?.body.contains("切换前的最后一句。") == true)
        }
    }
}
