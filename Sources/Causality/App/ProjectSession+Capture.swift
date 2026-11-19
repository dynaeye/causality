import Foundation
import CausalityCore

/// 讨论里的一句话往项目里落地：收成灵感、记成设定、插到锚点后。
enum MessageCapture {
    /// 从一段话里取一个能当标题的短句。
    static func title(_ text: String, limit: Int = 24) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flattened.isEmpty else { return InterfaceLanguage.label("来自讨论的一条") }
        if flattened.count <= limit { return flattened }
        return String(flattened.prefix(limit)) + "…"
    }
}

extension ProjectSession {
    /// 收为灵感卡：不带章，进侧栏的「灵感卡」，正文保留整段话。
    func captureMessageAsIdea(_ text: String) {
        guard let project else { return }
        let idea = StoryNode(status: .idea, title: MessageCapture.title(text), body: text)
        apply(ProjectMutations.appendNode(idea, to: project), name: "收为灵感卡")
        selectedNodeID = idea.id
    }

    /// 记为事实设定：草稿状态，挂在当前选中的场景上；没选中就只入设定库。
    func captureMessageAsSetting(_ text: String) {
        guard let project else { return }
        let setting = Setting(
            title: MessageCapture.title(text),
            text: text,
            isConfirmed: false,
            attachedNodeIDs: selectedNodeID.map { [$0] } ?? []
        )
        var operations = ProjectMutations.appendSetting(setting, to: project)
        if let nodeID = selectedNodeID {
            operations += ProjectMutations.updateNode(nodeID, in: project) { node in
                if !node.settingIDs.contains(setting.id) {
                    node.settingIDs.append(setting.id)
                }
            }
        }
        apply(operations, name: "记为事实设定")
    }

    /// 插到锚点后：沿用故事板点下的缝隙，整段话进卡片正文。
    /// 没有缝隙就不插，避免凭空决定位置。
    func insertMessageCard(_ text: String) {
        guard let project, let point = insertion else { return }
        var card = StoryNode(status: .idea, title: MessageCapture.title(text), chapterID: point.chapterID)
        card.body = text
        apply(
            ProjectMutations.insertCard(card, in: point.chapterID, at: point.index, in: project),
            name: "插到锚点后"
        )
        selectedNodeID = card.id
        insertion = nil
    }
}
