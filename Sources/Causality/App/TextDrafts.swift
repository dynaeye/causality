import Foundation
import CausalityCore
import SwiftUI

/// 长文本的编辑落点。
///
/// 直接绑模型的 `TextEditor` 会在拼音组字期间逐键提交；这里先把文本存进会话草稿，
/// 停输 400 ms 或失焦时再提交一次，输入法切换候选不会打断模型与派生重算。
enum TextDraftField: Hashable, Sendable {
    case nodeBody(NodeID)
    case nodeAnnotation(NodeID)
    case characterSummary(CharacterID)
    case characterNotes(CharacterID)

    var editName: String {
        switch self {
        case .nodeBody: InterfaceLanguage.label("修改正文")
        case .nodeAnnotation: InterfaceLanguage.label("修改注释")
        case .characterSummary: InterfaceLanguage.label("修改人物简介")
        case .characterNotes: InterfaceLanguage.label("修改人物备注")
        }
    }

    var coalescingKey: String {
        switch self {
        case .nodeBody(let id): "node:\(id):body"
        case .nodeAnnotation(let id): "node:\(id):annotation"
        case .characterSummary(let id): "character:\(id):summary"
        case .characterNotes(let id): "character:\(id):notes"
        }
    }

    /// 落点对应的模型文本；对象已经不在了就返回 nil。
    func read(in project: StoryProject) -> String? {
        switch self {
        case .nodeBody(let id): project.node(id)?.body
        case .nodeAnnotation(let id): project.node(id)?.annotation
        case .characterSummary(let id): project.characters.first { $0.id == id }?.summary
        case .characterNotes(let id): project.characters.first { $0.id == id }?.notes
        }
    }

    func operations(_ value: String, in project: StoryProject) -> [EditOperation]? {
        switch self {
        case .nodeBody(let id):
            guard project.node(id) != nil else { return nil }
            return ProjectMutations.updateNode(id, in: project) { $0.body = value }
        case .nodeAnnotation(let id):
            guard project.node(id) != nil else { return nil }
            return ProjectMutations.updateNode(id, in: project) { $0.annotation = value }
        case .characterSummary(let id):
            guard project.characters.contains(where: { $0.id == id }) else { return nil }
            return ProjectMutations.updateCharacter(id, in: project) { $0.summary = value }
        case .characterNotes(let id):
            guard project.characters.contains(where: { $0.id == id }) else { return nil }
            return ProjectMutations.updateCharacter(id, in: project) { $0.notes = value }
        }
    }
}

extension ProjectSession {
    /// 输入框绑这里：读草稿或模型，写只写草稿。
    func textDraftBinding(_ field: TextDraftField) -> Binding<String> {
        Binding(
            get: {
                if let draft = self.textDrafts[field] { return draft }
                guard let project = self.project else { return "" }
                return field.read(in: project) ?? ""
            },
            set: { newValue in
                self.stageTextDraft(newValue, for: field)
            }
        )
    }

    func stageTextDraft(_ value: String, for field: TextDraftField) {
        guard let project else { return }
        if field.read(in: project) == value {
            // 改回原样：撤掉草稿，不必写模型。
            textDraftTasks[field]?.cancel()
            textDraftTasks[field] = nil
            textDrafts[field] = nil
            return
        }
        guard textDrafts[field] != value else { return }
        textDrafts[field] = value
        textDraftTasks[field]?.cancel()
        textDraftTasks[field] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.commitTextDraft(field)
        }
    }

    /// 把一条草稿提交进模型。重复调用没有副作用。
    func commitTextDraft(_ field: TextDraftField) {
        textDraftTasks[field]?.cancel()
        textDraftTasks[field] = nil
        guard let value = textDrafts.removeValue(forKey: field) else { return }
        guard let project else { return }
        guard field.read(in: project) != value,
              let operations = field.operations(value, in: project) else { return }
        apply(operations, name: field.editName, coalescingKey: field.coalescingKey)
    }

    /// 保存、关闭、撤销、导出前把还没到点的草稿先落一笔。
    func commitAllTextDrafts() {
        for field in Array(textDrafts.keys) {
            commitTextDraft(field)
        }
    }
}
