import CausalityCore
import SwiftUI

// MARK: - 场景工程（v2a 六字段）

extension InspectorPane {
    /// 视角 / 时间 / 类型 / 张力 / 目标字数 / 写作状态。两列三行，未填时留空。
    func sceneEngine(_ node: StoryNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                engineField("视角") { povPicker(node) }
                engineField("时间") { storyTimeField(node) }
            }
            HStack(alignment: .top, spacing: 10) {
                engineField("类型") { sceneTypePicker(node) }
                engineField("张力") { tensionPicker(node) }
            }
            HStack(alignment: .top, spacing: 10) {
                engineField("目标字数") { targetWordsField(node) }
                engineField("写作状态") { writingStatePicker(node) }
            }
        }
    }

    private func engineField<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
            control()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func povPicker(_ node: StoryNode) -> some View {
        Picker("视角", selection: povBinding(node)) {
            Text("未定").tag(CharacterID?.none)
            ForEach(session.project?.characters ?? []) { character in
                Text(character.name).tag(CharacterID?.some(character.id))
            }
        }
        .labelsHidden()
        .controlSize(.small)
    }

    private func storyTimeField(_ node: StoryNode) -> some View {
        // 第一参数是占位提示，不是默认值：空着就显示这句，别让人以为是推算出来的。
        TextField(
            "输入事件日期",
            text: session.textBinding(node.id, \.storyTimeLabel, field: "storyTimeLabel")
        )
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .font(theme.fontMin)
        .help("这一场发生在故事里的什么时候。自由文字，比如「第三日黄昏」。")
    }

    private func sceneTypePicker(_ node: StoryNode) -> some View {
        Picker("类型", selection: sceneTypeBinding(node)) {
            Text("未定").tag(SceneType?.none)
            ForEach(SceneType.allCases, id: \.self) { type in
                Text(LocalizedStringKey(type.displayName)).tag(SceneType?.some(type))
            }
        }
        .labelsHidden()
        .controlSize(.small)
    }

    private func tensionPicker(_ node: StoryNode) -> some View {
        Picker("张力", selection: tensionBinding(node)) {
            Text("未定").tag(Int?.none)
            ForEach(1...5, id: \.self) { value in
                Text("\(value)/5").tag(Int?.some(value))
            }
        }
        .labelsHidden()
        .controlSize(.small)
    }

    private func targetWordsField(_ node: StoryNode) -> some View {
        TextField("不限", text: targetWordsTextBinding(node))
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .font(theme.fontMin)
            .help("这一场计划写多少字。只收数字，留空表示不限。")
    }

    private func writingStatePicker(_ node: StoryNode) -> some View {
        Picker("写作状态", selection: writingStateBinding(node)) {
            Text("未定").tag(WritingState?.none)
            ForEach(WritingState.allCases, id: \.self) { state in
                Text(LocalizedStringKey(state.displayName)).tag(WritingState?.some(state))
            }
        }
        .labelsHidden()
        .controlSize(.small)
    }

    // MARK: 绑定

    private func povBinding(_ node: StoryNode) -> Binding<CharacterID?> {
        Binding(
            get: { session.project?.node(node.id)?.pov },
            set: { value in session.updateNode(node.id) { $0.pov = value } }
        )
    }

    private func sceneTypeBinding(_ node: StoryNode) -> Binding<SceneType?> {
        Binding(
            get: { session.project?.node(node.id)?.sceneType },
            set: { value in session.updateNode(node.id) { $0.sceneType = value } }
        )
    }

    private func tensionBinding(_ node: StoryNode) -> Binding<Int?> {
        Binding(
            get: { session.project?.node(node.id)?.tension },
            set: { value in session.updateNode(node.id) { $0.tension = value } }
        )
    }

    private func writingStateBinding(_ node: StoryNode) -> Binding<WritingState?> {
        Binding(
            get: { session.project?.node(node.id)?.writingState },
            set: { value in session.updateNode(node.id) { $0.writingState = value } }
        )
    }

    /// 目标字数在界面上是文本框，落库是 Int?：清空即不限。
    private func targetWordsTextBinding(_ node: StoryNode) -> Binding<String> {
        Binding(
            get: {
                guard let value = session.project?.node(node.id)?.targetWords else { return "" }
                return String(value)
            },
            set: { text in
                let digits = text.filter { $0.isNumber }
                let value = digits.isEmpty ? nil : Int(digits)
                session.updateNode(node.id, coalescingKey: "node:\(node.id):targetWords") { node in
                    node.targetWords = value
                }
            }
        )
    }

    // MARK: 折叠时的摘要

    func basicsHint(_ node: StoryNode) -> String {
        var parts = [session.chapterTitle(node.chapterID)]
        if node.isEntry { parts.append(InterfaceLanguage.label("入口")) }
        if node.status == .idea { parts.append(InterfaceLanguage.label("灵感卡")) }
        return parts.joined(separator: " · ")
    }

    func engineHint(_ node: StoryNode) -> String {
        var parts: [String] = []
        if let id = node.pov,
           let name = session.project?.characters.first(where: { $0.id == id })?.name {
            parts.append(name)
        }
        let time = node.storyTimeLabel.trimmingCharacters(in: .whitespaces)
        if !time.isEmpty { parts.append(time) }
        if let type = node.sceneType { parts.append(InterfaceLanguage.label(type.displayName)) }
        if let tension = node.tension {
            parts.append(String(format: InterfaceLanguage.label("张力 %lld/5"), tension))
        }
        if let target = node.targetWords {
            parts.append(String(format: InterfaceLanguage.label("目标 %lld 字"), target))
        }
        if let state = node.writingState { parts.append(InterfaceLanguage.label(state.displayName)) }
        return parts.isEmpty ? InterfaceLanguage.label("未填") : parts.joined(separator: " · ")
    }

    func castHint(_ node: StoryNode) -> String {
        let index = session.projectIndex
        let names = node.characterIDs.compactMap { index?.characterByID[$0]?.name }
        let places = node.placeIDs.compactMap { index?.placeByID[$0]?.name }
        var parts: [String] = []
        let list = InterfaceLanguage.listSeparator
        if !names.isEmpty { parts.append(names.joined(separator: list)) }
        if !places.isEmpty { parts.append(places.joined(separator: list)) }
        return parts.isEmpty ? InterfaceLanguage.label("未填") : parts.joined(separator: " · ")
    }

    func settingsHint(_ node: StoryNode) -> String {
        node.settingIDs.isEmpty
            ? InterfaceLanguage.label("未挂设定")
            : String(format: InterfaceLanguage.label("%lld 条"), node.settingIDs.count)
    }

    func coverHint(_ node: StoryNode) -> String {
        guard let id = node.coverAssetID, let asset = session.project?.asset(id) else {
            return InterfaceLanguage.label("未选图")
        }
        return asset.caption.isEmpty ? asset.fileName : asset.caption
    }

    func edgesHint(_ node: StoryNode) -> String {
        let index = session.projectIndex
        let outgoing = index?.outgoingEdges(of: node.id).count ?? 0
        let incoming = index?.incomingEdges(of: node.id).count ?? 0
        if outgoing == 0, incoming == 0 { return InterfaceLanguage.label("未接线") }
        return String(format: InterfaceLanguage.label("去 %lld · 来 %lld"), outgoing, incoming)
    }

    func notesHint(_ node: StoryNode) -> String {
        let text = node.annotation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return InterfaceLanguage.label("空") }
        return String(text.prefix(24)).replacingOccurrences(of: "\n", with: " ")
    }
}
