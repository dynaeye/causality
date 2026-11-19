import Foundation
import CausalityCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 故事板上的卡片操作

extension ProjectSession {
    /// 给这张卡选一张配图。面板挂成 sheet，App 在后台时也点得动。
    func pickImage(for nodeID: NodeID) {
        Task {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .webP]
            panel.allowsMultipleSelection = false
            guard let url = await FilePanels.url(panel) else { return }
            importImage(from: url, for: nodeID)
        }
    }

    /// 故事板缝隙里「插一张带图的卡」：先选图，再按写作或文件名落卡。
    func insertCardWithImage(at point: CardInsertionPoint, title: String) {
        Task {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .webP]
            panel.allowsMultipleSelection = false
            guard let url = await FilePanels.url(panel) else { return }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            insertCard(
                at: point,
                title: trimmed.isEmpty ? url.deletingPathExtension().lastPathComponent : trimmed
            )
            if let id = selectedNodeID {
                importImage(from: url, for: id)
            }
        }
    }

    func cards(in chapterID: ChapterID) -> [StoryNode] {
        // 走会话里已经建好的索引：故事板一处 body 会问上百次，重建索引会平方级放大。
        guard let index = projectIndex ?? project.map({ $0.makeIndex() }) else { return [] }
        return index.nodes(in: chapterID)
    }

    func cardCount(in chapterID: ChapterID) -> Int {
        cards(in: chapterID).count
    }

    /// 在某一处缝隙插一张卡。默认是留在板上的念头。
    func insertCard(at point: CardInsertionPoint, title: String, status: NodeStatus = .idea) {
        guard let project else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let node = StoryNode(status: status, title: trimmed, chapterID: point.chapterID)
        apply(
            ProjectMutations.insertCard(node, in: point.chapterID, at: point.index, in: project),
            name: "插入卡片"
        )
        selectedNodeID = node.id
        insertion = nil
    }

    func moveCard(_ id: NodeID, to chapterID: ChapterID, at index: Int) {
        guard let project else { return }
        apply(
            ProjectMutations.moveCard(id, toChapter: chapterID, at: index, in: project),
            name: "移动卡片"
        )
    }

    func moveCardToEnd(_ id: NodeID, chapterID: ChapterID) {
        guard let project else { return }
        apply(
            ProjectMutations.moveNode(id, toChapter: chapterID, at: nil, in: project),
            name: "移动卡片"
        )
    }

    @discardableResult
    func addCharacter(name: String = InterfaceLanguage.label("新人物")) -> CharacterID {
        guard let project else { return CharacterID() }
        let character = StoryCharacter(name: name)
        apply(ProjectMutations.appendCharacter(character, to: project), name: "新建人物")
        return character.id
    }

    func updateCharacter(_ id: CharacterID, coalescingKey: String? = nil, _ body: @escaping (inout StoryCharacter) -> Void) {
        guard let project else { return }
        apply(
            ProjectMutations.updateCharacter(id, in: project, body),
            name: "修改人物",
            coalescingKey: coalescingKey
        )
    }

    func characterPoint(for id: CharacterID) -> CanvasPoint? {
        project?.characterCanvas[id]
    }

    func moveCharacter(_ id: CharacterID, to point: CanvasPoint) {
        guard let project else { return }
        apply(
            ProjectMutations.setCharacterCanvasPoint(point, for: id, in: project),
            name: "移动人物",
            coalescingKey: "characterCanvas:\(id)"
        )
    }

    func addRelation(_ kind: RelationKind, from id: CharacterID, to target: CharacterID) {
        guard let project else { return }
        apply(
            ProjectMutations.addRelation(kind, from: id, to: target, in: project),
            name: "添加人物关系"
        )
    }

    func removeRelation(_ relationID: UUID, from id: CharacterID) {
        guard let project else { return }
        apply(
            ProjectMutations.removeRelation(relationID, from: id, in: project),
            name: "删除人物关系"
        )
    }

    func deleteCharacter(_ id: CharacterID) {
        guard let project else { return }
        apply(ProjectMutations.deleteCharacter(id, in: project), name: "删除人物")
    }

    func convertCard(_ id: NodeID, to status: NodeStatus) {
        updateNode(id) { node in
            node.status = status
            if status == .idea {
                node.kind = .event
            }
        }
    }

    func setInsertion(_ point: CardInsertionPoint?) {
        insertion = point
        if let anchor = point?.anchorNodeID {
            selectedNodeID = anchor
        }
    }
}

extension ProjectSession {
    /// 并列组的手动覆盖。传 nil 恢复自动判定。
    func setCardGroupOverride(_ id: NodeID, _ value: String?) {
        guard let project else { return }
        apply(
            ProjectMutations.setCardGroupOverride(id, value: value, in: project),
            name: value == nil ? "恢复自动并列组" : "调整并列组"
        )
    }
}
