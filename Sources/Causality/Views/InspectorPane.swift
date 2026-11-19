import AppKit
import CausalityCore
import SwiftUI

struct InspectorPane: View {
    @Environment(\.theme) var theme
    @Bindable var session: ProjectSession

    @State var newCharacterName: String = ""
    @State var newSettingTitle: String = ""
    @State var editingSettingID: SettingID?
    @State var settingDraftTitle: String = ""
    @State var settingDraftText: String = ""
    @State var showingAddEdge = false

    // 右栏各段的折叠状态。默认只展开摘要、场景工程与正文，其余收成一行。
    @AppStorage("causal.inspector.section.basics") var basicsCollapsed = true
    @AppStorage("causal.inspector.section.engine") var engineCollapsed = false
    @AppStorage("causal.inspector.section.cast") var castCollapsed = true
    @AppStorage("causal.inspector.section.settings") var settingsCollapsed = true
    @AppStorage("causal.inspector.section.cover") var coverCollapsed = true
    @AppStorage("causal.inspector.section.edges") var edgesCollapsed = true
    @AppStorage("causal.inspector.section.notes") var notesCollapsed = true
    @AppStorage("causal.inspector.section.threads") var threadsCollapsed = true

    var node: StoryNode? {
        guard let id = session.selectedNodeID else { return nil }
        return session.project?.node(id)
    }

    var body: some View {
        Group {
            if let node {
                VStack(spacing: 0) {
                    // 与大纲的章节头一套：标题 + 一行说明 + 下面一条横线。
                    header(node)
                    Rectangle().fill(theme.border).frame(height: 1)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            summaryField(node)
                            InspectorSection(
                                title: "场景工程",
                                hint: engineHint(node),
                                collapsed: $engineCollapsed
                            ) {
                                sceneEngine(node)
                            }
                            bodySection(node)
                            InspectorSection(
                                title: "基础",
                                hint: basicsHint(node),
                                collapsed: $basicsCollapsed
                            ) {
                                basics(node)
                            }
                            InspectorSection(
                                title: "人物与地点",
                                hint: castHint(node),
                                collapsed: $castCollapsed
                            ) {
                                castSection(node)
                            }
                            InspectorSection(
                                title: "线索",
                                hint: threadHint(node),
                                collapsed: $threadsCollapsed
                            ) {
                                threadsSection(node)
                            }
                            InspectorSection(
                                title: "事实设定",
                                hint: settingsHint(node),
                                collapsed: $settingsCollapsed
                            ) {
                                settingSection(node)
                            }
                            InspectorSection(
                                title: "配图",
                                hint: coverHint(node),
                                collapsed: $coverCollapsed
                            ) {
                                coverSection(node)
                            }
                            InspectorSection(
                                title: "去向",
                                hint: edgesHint(node),
                                collapsed: $edgesCollapsed
                            ) {
                                edgeSection(node)
                            }
                            InspectorSection(
                                title: "注释",
                                hint: notesHint(node),
                                collapsed: $notesCollapsed
                            ) {
                                annotationSection(node)
                            }
                            deleteSection(node)
                        }
                        .padding(14)
                    }
                    .scrollIndicators(.visible)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.and.text.magnifyingglass")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(theme.textTertiary)
                    Text("未选中场景")
                        .font(theme.fontBody)
                        .foregroundStyle(theme.textSecondary)
                    Text("在故事板、大纲或故事图里选一张卡；也可以直接开新的")
                        .font(theme.fontMin)
                        .foregroundStyle(theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    HStack(spacing: 8) {
                        Button {
                            session.addChapter()
                        } label: {
                            Label("新建章节", systemImage: "book.closed")
                        }
                        Button {
                            session.addIdeaCard()
                        } label: {
                            Label("新建灵感", systemImage: "lightbulb")
                        }
                    }
                    .controlSize(.regular)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(theme.surface)
        .sheet(isPresented: $showingAddEdge) {
            if let node {
                AddEdgeSheet(session: session, source: node)
            }
        }
    }

    // MARK: 头部

    func header(_ node: StoryNode) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                TitleField(session: session, node: node)
                Spacer(minLength: 6)
                Picker("类型", selection: session.kindBinding(node.id)) {
                    ForEach(NodeKind.allCases, id: \.self) { kind in
                        Text(LocalizedStringKey(kind.displayName)).tag(kind)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 86)
            }
            Text(subtitle(node))
                .font(theme.fontMin)
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subtitle(_ node: StoryNode) -> String {
        var parts = [InterfaceLanguage.label(node.kind.displayName)]
        if node.status == .idea { parts.append(InterfaceLanguage.label("灵感卡")) }
        parts.append(
            String(
                format: InterfaceLanguage.label("正文 %@"),
                WordCountText.text(session.wordCounts.count(of: node.id))
            )
        )
        parts.append(
            String(format: InterfaceLanguage.label("出场 %lld 人"), node.characterIDs.count)
        )
        return parts.joined(separator: " · ")
    }

    func summaryField(_ node: StoryNode) -> some View {
        TextField("一句摘要", text: session.textBinding(node.id, \.summary, field: "summary"))
            .textFieldStyle(.roundedBorder)
            .font(theme.fontBody)
    }

    func basics(_ node: StoryNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("章节") {
                Picker("章节", selection: session.chapterBinding(node.id)) {
                    Text("未分章").tag(ChapterID?.none)
                    ForEach(session.project?.chapters ?? []) { chapter in
                        Text(chapter.title).tag(ChapterID?.some(chapter.id))
                    }
                }
                .labelsHidden()
            }
            HStack(spacing: 10) {
                Toggle("故事入口", isOn: session.intBinding(node.id, \.isEntry))
                    .toggleStyle(.checkbox)
                Spacer()
                if node.status == .idea {
                    Button("写成正式场景") { setIdea(node, false) }
                        .buttonStyle(.link)
                } else {
                    Button("退回成念头") { setIdea(node, true) }
                        .buttonStyle(.link)
                }
            }
        }
    }

    func bodySection(_ node: StoryNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("正文")
                .font(theme.fontMin)
                .foregroundStyle(.secondary)
            TextDraftEditor(session: session, field: .nodeBody(node.id))
                .font(theme.fontBody)
                .frame(minHeight: 150)
                .padding(4)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            bodyWordCount(node)
        }
    }

    /// 正文下的实时字数；设了「目标字数」时顺带给一条进度。
    private func bodyWordCount(_ node: StoryNode) -> some View {
        let words = session.wordCounts.count(of: node.id)
        return HStack(spacing: 8) {
            Text(WordCountText.text(words))
            if let target = node.targetWords, target > 0 {
                ProgressView(value: Double(words), total: Double(target))
                    .progressViewStyle(.linear)
                    .tint(theme.accent)
                    .frame(width: 84)
                Text("目标 \(WordCountText.text(target))")
            }
            Spacer(minLength: 0)
        }
        .font(theme.fontMin)
        .foregroundStyle(theme.textTertiary)
        .help("中文按字、英文按词，标点与空白不计。")
    }

    // MARK: 人物与地点

    func castSection(_ node: StoryNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("出场人物")
                .font(theme.fontMin)
                .foregroundStyle(.secondary)
            tokenRow(
                items: (session.project?.characters ?? []).map { (id: $0.id.rawValue.uuidString, title: $0.name) },
                selected: node.characterIDs.map(\.rawValue.uuidString)
            ) { idString, _ in
                guard let id = CharacterID(string: idString) else { return }
                var ids = node.characterIDs
                if let index = ids.firstIndex(of: id) {
                    ids.remove(at: index)
                } else {
                    ids.append(id)
                }
                updateCharacterIDs(node, ids)
            }
            HStack {
                TextField(
                    "新人物",
                    text: Binding(
                        get: { newCharacterName },
                        set: { newCharacterName = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                Button("添加") { addCharacter(to: node) }
                    .disabled(newCharacterName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(theme.fontMin)

            Text("地点")
                .font(theme.fontMin)
                .foregroundStyle(.secondary)
            tokenRow(
                items: (session.project?.places ?? []).map { (id: $0.id.rawValue.uuidString, title: $0.name) },
                selected: node.placeIDs.map(\.rawValue.uuidString)
            ) { idString, _ in
                guard let id = PlaceID(string: idString) else { return }
                var ids = node.placeIDs
                if let index = ids.firstIndex(of: id) {
                    ids.remove(at: index)
                } else {
                    ids.append(id)
                }
                updatePlaceIDs(node, ids)
            }
        }
    }

    func tokenRow(
        items: [(id: String, title: String)],
        selected: [String],
        onTap: @escaping (String, String) -> Void
    ) -> some View {
        FlowRow(spacing: 5) {
            ForEach(items, id: \.id) { item in
                let isSelected = selected.contains(item.id)
                Button {
                    onTap(item.id, item.title)
                } label: {
                    Text(item.title)
                        .font(theme.fontMin)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            isSelected
                                ? Color.accentColor.opacity(0.18)
                                : Color.secondary.opacity(0.1),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 标题

/// 点一下才变成输入框。
/// 一直挂着 TextField 的话，窗口一出来它就是第一响应者，任何误触键盘都会直接改掉作品里的标题。
struct TitleField: View {
    @Environment(\.theme) private var theme
    let session: ProjectSession
    let node: StoryNode

    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("标题", text: session.textBinding(node.id, \.title, field: "title"))
                    .textFieldStyle(.plain)
                    .font(theme.fontTitle)
                    .focused($focused)
                    .onAppear { focused = true }
                    .onSubmit { editing = false }
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { editing = false }
                    }
            } else {
                Text(verbatim: node.title.isEmpty ? InterfaceLanguage.label("未命名场景") : node.title)
                    .font(theme.fontTitle)
                    .foregroundStyle(node.title.isEmpty ? theme.textTertiary : theme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { editing = true }
                    .help("点一下改标题")
            }
        }
    }
}

// MARK: - 新增连线

struct AddEdgeSheet: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession
    let source: StoryNode

    @Environment(\.dismiss) private var dismiss
    @State var targetID: NodeID?
    @State var kind: EdgeKind = .choice
    @State var label: String = ""
    @State var condition: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("从「\(source.title)」出发")
                .font(theme.fontCardTitle)

            Picker("目标场景", selection: $targetID) {
                Text("选择…").tag(NodeID?.none)
                ForEach(candidates) { node in
                    Text("\(session.chapterTitle(node.chapterID)) · \(node.title)")
                        .tag(NodeID?.some(node.id))
                }
            }

            Picker("类型", selection: $kind) {
                ForEach(EdgeKind.allCases, id: \.self) { value in
                    Text(LocalizedStringKey(value.displayName)).tag(value)
                }
            }
            .pickerStyle(.segmented)

            TextField("选项原文 / 原因", text: $label)
                .textFieldStyle(.roundedBorder)
            TextField("附加条件（可留空）", text: $condition)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("连接") {
                    guard let targetID else { return }
                    session.connect(from: source.id, to: targetID, kind: kind, label: label, condition: condition)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(targetID == nil)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private var candidates: [StoryNode] {
        (session.project?.nodes ?? []).filter { $0.id != source.id }
    }
}
