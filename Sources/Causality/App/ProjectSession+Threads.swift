import Foundation
import CausalityCore

// MARK: - 线索账本

extension ProjectSession {
    var threads: [StoryThread] {
        project?.threads ?? []
    }

    var focusedThread: StoryThread? {
        guard let id = focusedThreadID else { return nil }
        return threads.first { $0.id == id }
    }

    func openThreads(focus: ThreadID? = nil) {
        guard project != nil else { return }
        isWriting = false
        isAuditing = false
        isSynopsizing = false
        isThreading = true
        if let focus {
            focusedThreadID = focus
        } else if focusedThreadID == nil {
            focusedThreadID = threads.first?.id
        }
    }

    func closeThreads() {
        isThreading = false
    }

    @discardableResult
    func addThread(name: String, kind: ThreadKind) -> ThreadID? {
        guard let project else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let thread = StoryThread(
            name: trimmed.isEmpty ? InterfaceLanguage.label("新线索") : trimmed,
            kind: kind
        )
        apply(ProjectMutations.appendThread(thread, to: project), name: "新建线索")
        focusedThreadID = thread.id
        return thread.id
    }

    func deleteThread(_ id: ThreadID) {
        guard let project else { return }
        apply(ProjectMutations.deleteThread(id, in: project), name: "删除线索")
        if focusedThreadID == id {
            focusedThreadID = threads.first { $0.id != id }?.id
        }
    }

    func addThreadEntry(_ threadID: ThreadID, nodeID: NodeID, role: ThreadRole, text: String = "") {
        guard let project else { return }
        let entry = ThreadEntry(nodeID: nodeID, role: role, text: text)
        apply(
            ProjectMutations.addThreadEntry(entry, threadID: threadID, in: project),
            name: "记在线索上"
        )
    }

    func updateThreadEntryText(_ threadID: ThreadID, entryID: UUID, text: String) {
        guard let project else { return }
        apply(
            ProjectMutations.updateThread(threadID, in: project) { thread in
                if let index = thread.entries.firstIndex(where: { $0.id == entryID }) {
                    thread.entries[index].text = text
                }
            },
            name: "修改线索注记",
            coalescingKey: "thread:\(threadID.rawValue.uuidString):\(entryID.uuidString)"
        )
    }

    func setThreadKind(_ threadID: ThreadID, kind: ThreadKind) {
        guard let project else { return }
        apply(
            ProjectMutations.updateThread(threadID, in: project) { $0.kind = kind },
            name: "修改线索类型"
        )
    }

    func removeThreadEntry(_ threadID: ThreadID, entryID: UUID) {
        guard let project else { return }
        apply(
            ProjectMutations.removeThreadEntry(entryID, threadID: threadID, in: project),
            name: "移出线索"
        )
    }

    /// 这张卡在哪些线索上。
    func threads(at nodeID: NodeID) -> [StoryThread] {
        threads.filter { thread in thread.entries.contains { $0.nodeID == nodeID } }
    }

    func entries(of thread: StoryThread, at nodeID: NodeID) -> [ThreadEntry] {
        thread.entries.filter { $0.nodeID == nodeID }
    }
}
