import Foundation
import CausalityCore

// MARK: - 写作模式的进入、翻场与落卡

extension ProjectSession {
    var currentWritingScene: WritingScene? {
        guard let id = selectedNodeID else { return nil }
        return writingScenes.first { $0.id == id }
    }

    var writingNeighbors: (previous: WritingScene?, next: WritingScene?) {
        guard let index = writingScenes.firstIndex(where: { $0.id == selectedNodeID }) else {
            return (nil, nil)
        }
        return (
            index > 0 ? writingScenes[index - 1] : nil,
            index + 1 < writingScenes.count ? writingScenes[index + 1] : nil
        )
    }

    func toggleWritingMode() {
        if isWriting {
            isWriting = false
        } else {
            enterWriting()
        }
    }

    func enterWriting() {
        guard project != nil else { return }
        isAuditing = false
        isWriting = true
        guard !writingScenes.isEmpty else { return }
        if let id = selectedNodeID, writingScenes.contains(where: { $0.id == id }) {
            return
        }
        if let id = lastWritingSceneID(), let scene = writingScenes.first(where: { $0.id == id }) {
            setWritingScene(scene)
            return
        }
        if let first = writingScenes.first {
            setWritingScene(first)
        }
    }

    func setWritingScene(_ scene: WritingScene) {
        selectedNodeID = scene.id
        focusedChapterID = scene.chapterID
        rememberWritingScene()
    }

    /// `⌘↑ / ⌘↓`：按写作顺序翻场，到头就停在原地。
    func stepWriting(_ offset: Int) {
        guard isWriting, !writingScenes.isEmpty else { return }
        let index = writingScenes.firstIndex { $0.id == selectedNodeID } ?? 0
        let target = min(max(index + offset, 0), writingScenes.count - 1)
        setWritingScene(writingScenes[target])
    }

    /// 在当前场后面新建一场，同章、走顺序表。
    @discardableResult
    func newNextWritingScene() -> NodeID? {
        guard let project, let current = currentWritingScene, let chapterID = current.chapterID else {
            return nil
        }
        var card = StoryNode(title: InterfaceLanguage.label("新场景"), chapterID: chapterID)
        card.status = .draft
        let operations = ProjectMutations.insertCard(
            card,
            in: chapterID,
            at: insertIndex(after: current, in: project),
            in: project
        )
        apply(operations, name: "新建下一场")
        selectedNodeID = card.id
        return card.id
    }

    /// `⇧⌘D`：从本场分叉。新卡接在当前场后面，并连一条空选项的 choice 线，等作者在底部写选项。
    @discardableResult
    func forkWritingScene() -> NodeID? {
        guard let project, let current = currentWritingScene, let chapterID = current.chapterID else {
            return nil
        }
        var card = StoryNode(title: InterfaceLanguage.label("另一条路"), chapterID: chapterID)
        card.status = .draft
        var working = project
        let insertion = ProjectMutations.insertCard(
            card,
            in: chapterID,
            at: insertIndex(after: current, in: project),
            in: working
        )
        try? ProjectEditing.apply(insertion, to: &working)
        let edge = ProjectMutations.connect(
            from: current.id,
            to: card.id,
            kind: .choice,
            label: "",
            in: working
        )
        apply(insertion + edge, name: "从本场分叉")
        selectedNodeID = card.id
        return card.id
    }

    private func insertIndex(after scene: WritingScene, in project: StoryProject) -> Int {
        guard let chapterID = scene.chapterID, let chapter = project.chapter(chapterID) else {
            return 0
        }
        return (chapter.order.firstIndex(of: scene.id).map { $0 + 1 }) ?? chapter.order.count
    }

    func lastWritingSceneID() -> NodeID? {
        guard let project,
              let raw = UserDefaults.standard.string(forKey: Self.writingSceneKey(projectID: project.id)),
              let uuid = UUID(uuidString: raw) else { return nil }
        return NodeID(rawValue: uuid)
    }

    /// 选中哪一场就记哪一场，下次进写作模式接着写。
    func rememberWritingScene() {
        guard isWriting, let id = selectedNodeID, let project else { return }
        UserDefaults.standard.set(
            id.rawValue.uuidString,
            forKey: Self.writingSceneKey(projectID: project.id)
        )
    }

    private static func writingSceneKey(projectID: UUID) -> String {
        "causal.writing.lastScene.\(projectID.uuidString)"
    }
}
