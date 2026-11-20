import AppKit
import CausalityCore
import SwiftUI

extension InspectorPane {
    // MARK: 事实设定

    func settingSection(_ node: StoryNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("事实设定")
            ForEach(node.settingIDs.compactMap { session.project?.setting($0) }) { setting in
                settingRow(setting, node: node)
            }
            newSettingField(node)
        }
    }

    private func settingRow(_ setting: Setting, node: StoryNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    if editingSettingID == setting.id {
                        editingSettingID = nil
                    } else {
                        editingSettingID = setting.id
                        settingDraftTitle = setting.title
                        settingDraftText = setting.text
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: settingIcon(setting))
                            .foregroundStyle(setting.isConfirmed ? Color.accentColor : .secondary)
                            .font(theme.fontMin)
                        Text(setting.title)
                            .font(theme.fontBody)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                settingMenu(setting, node: node)
            }

            if editingSettingID == setting.id {
                settingEditor(setting)
            } else if !setting.text.isEmpty {
                Text(setting.text)
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(3)
                    .padding(.leading, 18)
            }
        }
    }

    /// 事实设定的正文就地编辑：标题与说明都存在设定本身，改完走编辑操作提交。
    private func settingEditor(_ setting: Setting) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("事实设定标题", text: $settingDraftTitle)
                .textFieldStyle(.roundedBorder)
                .font(theme.fontMin)
            TextEditor(text: $settingDraftText)
                .font(theme.fontMin)
                .frame(minHeight: 56, maxHeight: 110)
                .padding(4)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(theme.border, lineWidth: 1)
                }
            HStack(spacing: 8) {
                Button("保存") { commitSettingEdit(setting) }
                    .disabled(settingDraftTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("取消") { editingSettingID = nil }
            }
            .font(theme.fontMin)
        }
        .padding(.leading, 18)
    }

    private func commitSettingEdit(_ setting: Setting) {
        guard let project = session.project else { return }
        let title = settingDraftTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let text = settingDraftText
        session.apply(
            ProjectMutations.updateSetting(setting.id, in: project) { value in
                value.title = title
                value.text = text
            },
            name: InterfaceLanguage.label("编辑事实设定")
        )
        editingSettingID = nil
    }

    private func settingIcon(_ setting: Setting) -> String {
        if setting.isLocked { return "lock.fill" }
        return setting.isConfirmed ? "checkmark.seal.fill" : "questionmark.circle"
    }

    private func settingMenu(_ setting: Setting, node: StoryNode) -> some View {
        Menu {
            Button(setting.isConfirmed ? LocalizedStringKey("取消确认") : LocalizedStringKey("确认")) {
                guard let project = session.project else { return }
                session.apply(
                    ProjectMutations.setSettingConfirmed(setting.id, !setting.isConfirmed, in: project),
                    name: InterfaceLanguage.label("修改事实设定状态")
                )
            }
            Button(setting.isLocked ? LocalizedStringKey("解锁") : LocalizedStringKey("锁定")) {
                guard let project = session.project else { return }
                session.apply(
                    ProjectMutations.setSettingLocked(setting.id, !setting.isLocked, in: project),
                    name: InterfaceLanguage.label("修改事实设定锁")
                )
            }
            Divider()
            Button("解除挂载") {
                guard let project = session.project else { return }
                session.apply(
                    ProjectMutations.detachSetting(setting.id, from: node.id, in: project),
                    name: InterfaceLanguage.label("解除事实设定挂载")
                )
            }
            if !setting.isLocked {
                Button("删除", role: .destructive) {
                    deleteSetting(setting)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22)
    }

    private func deleteSetting(_ setting: Setting) {
        guard let project = session.project,
              let operations = try? ProjectMutations.deleteSetting(setting.id, in: project) else { return }
        session.apply(operations, name: InterfaceLanguage.label("删除事实设定"))
    }

    private func newSettingField(_ node: StoryNode) -> some View {
        HStack {
            TextField("新建事实设定并挂到此场景", text: $newSettingTitle)
                .textFieldStyle(.roundedBorder)
            Button("添加") { addSetting(to: node) }
                .disabled(newSettingTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .font(theme.fontMin)
    }

    // MARK: 配图

    func coverSection(_ node: StoryNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("配图")
            if let assetID = node.coverAssetID, let asset = session.project?.asset(assetID) {
                CoverThumbnail(asset: asset, packageURL: session.packageURL, maxPixel: 640)
                    .frame(height: 120)
                TextField("配图说明", text: captionBinding(asset))
                    .textFieldStyle(.roundedBorder)
                    .font(theme.fontMin)
            }
            HStack {
                Button("选择图片…") { pickImage(for: node) }
                    .controlSize(.small)
                if node.coverAssetID != nil {
                    Button("移除") {
                        session.updateNode(node.id) { value in value.coverAssetID = nil }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func captionBinding(_ asset: Asset) -> Binding<String> {
        Binding(
            get: { self.session.project?.asset(asset.id)?.caption ?? "" },
            set: { newValue in
                guard let project = self.session.project,
                      let before = project.asset(asset.id) else { return }
                var after = before
                after.caption = newValue
                self.session.apply(
                    [.replaceAsset(before: before, after: after)],
                    name: InterfaceLanguage.label("修改配图说明"),
                    coalescingKey: "asset:\(asset.id):caption"
                )
            }
        )
    }

    // MARK: 发展线

    func edgeSection(_ node: StoryNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("去向")
                    .help("这个场景之后走到哪里")
                Spacer()
                Button {
                    showingAddEdge = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
            }

            ForEach(outgoingEdges(of: node)) { edge in
                outgoingEdgeRow(edge)
            }

            let incoming = incomingEdges(of: node)
            if !incoming.isEmpty {
                sectionLabel("来源")
                    .help("哪些场景走到这个场景")
                ForEach(incoming) { edge in
                    incomingEdgeRow(edge)
                }
            }
        }
    }

    private func outgoingEdges(of node: StoryNode) -> [StoryEdge] {
        (session.project?.edges ?? []).filter { $0.from == node.id }
    }

    private func incomingEdges(of node: StoryNode) -> [StoryEdge] {
        (session.project?.edges ?? []).filter { $0.to == node.id }
    }

    private func outgoingEdgeRow(_ edge: StoryEdge) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Button {
                    guard let project = session.project else { return }
                    let operations = edge.isMainline
                        ? ProjectMutations.clearMainline(edge.id, in: project)
                        : ProjectMutations.setMainline(edge.id, in: project)
                    session.apply(operations, name: InterfaceLanguage.label(edge.isMainline ? "取消主线" : "设为主线"))
                } label: {
                    Image(systemName: edge.isMainline ? "arrow.up.right.circle.fill" : "arrow.up.right.circle")
                        .font(theme.fontMin)
                        .foregroundStyle(edge.isMainline ? theme.accent : theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help(LocalizedStringKey(edge.isMainline ? "这条是这个选择点的主线去向（点一下取消）" : "把这个选择点的主线去向指到这条线"))
                Text(LocalizedStringKey(edge.kind.displayName))
                    .font(theme.fontMin)
                    .foregroundStyle(theme.lineColor(for: edge.kind))
                Text(targetLabel(edge))
                    .font(theme.fontMin)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    guard let project = session.project else { return }
                    session.apply(ProjectMutations.disconnect(edge.id, in: project), name: InterfaceLanguage.label("删除发展线"))
                } label: {
                    Image(systemName: "trash")
                        .font(theme.fontMin)
                }
                .buttonStyle(.plain)
            }
            TextField("连线文字", text: labelBinding(edge))
                .textFieldStyle(.roundedBorder)
                .font(theme.fontMin)
        }
        .padding(6)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private func targetLabel(_ edge: StoryEdge) -> String {
        let node = session.project?.node(edge.to)
        return session.chapterTitle(node?.chapterID) + " · " + (node?.title ?? InterfaceLanguage.label("未知"))
    }

    private func labelBinding(_ edge: StoryEdge) -> Binding<String> {
        Binding(
            get: { self.session.project?.edge(edge.id)?.label ?? "" },
            set: { newValue in
                guard let project = self.session.project else { return }
                self.session.apply(
                    ProjectMutations.updateEdge(edge.id, in: project) { $0.label = newValue },
                    name: InterfaceLanguage.label("修改连线文字"),
                    coalescingKey: "edge:\(edge.id):label"
                )
            }
        )
    }

    private func incomingEdgeRow(_ edge: StoryEdge) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(LocalizedStringKey(edge.kind.displayName))
                    .font(theme.fontMin)
                    .foregroundStyle(theme.lineColor(for: edge.kind))
                Button {
                    session.selectedNodeID = edge.from
                } label: {
                    Text(session.project?.node(edge.from)?.title ?? InterfaceLanguage.label("未知"))
                        .font(theme.fontMin)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                .buttonStyle(.link)
                .help("跳到这个来源场景")
                Spacer()
                Menu {
                    ForEach(EdgeKind.allCases, id: \.self) { kind in
                        Button(LocalizedStringKey(kind.displayName)) {
                            guard let project = session.project else { return }
                            session.apply(
                                ProjectMutations.updateEdge(edge.id, in: project) { $0.kind = kind },
                                name: InterfaceLanguage.label("修改连线类型")
                            )
                        }
                    }
                    Divider()
                    Menu("换来源场景") {
                        ForEach(candidateSources(for: edge)) { node in
                            Button(node.title.isEmpty ? InterfaceLanguage.label("未命名") : node.title) {
                                changeSource(of: edge, to: node.id)
                            }
                        }
                    }
                    Divider()
                    Button("删除这条线", role: .destructive) {
                        guard let project = session.project else { return }
                        session.apply(ProjectMutations.disconnect(edge.id, in: project), name: InterfaceLanguage.label("删除发展线"))
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20)
            }
            TextField("连线文字", text: labelBinding(edge))
                .textFieldStyle(.roundedBorder)
                .font(theme.fontMin)
        }
        .padding(6)
        .background(theme.border.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
    }

    private func candidateSources(for edge: StoryEdge) -> [StoryNode] {
        (session.project?.nodes ?? []).filter { $0.id != edge.to && $0.id != edge.from }
    }

    private func changeSource(of edge: StoryEdge, to nodeID: NodeID) {
        guard let project = session.project else { return }
        session.apply(
            ProjectMutations.updateEdge(edge.id, in: project) { $0.from = nodeID },
            name: InterfaceLanguage.label("更换来源场景")
        )
    }

    func deleteSection(_ node: StoryNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
            Button("删除这张卡", role: .destructive) { delete(node) }
                .buttonStyle(.link)
                .font(theme.fontMin)
        }
        .padding(.top, 4)
    }

    func annotationSection(_ node: StoryNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("注释")
            TextDraftEditor(session: session, field: .nodeAnnotation(node.id))
                .font(theme.fontMin)
                .frame(minHeight: 60)
                .padding(4)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(theme.fontMin)
            .foregroundStyle(.secondary)
    }

    // MARK: 动作

    func setEntry(_ node: StoryNode, _ value: Bool) {
        guard let project = session.project else { return }
        session.apply(ProjectMutations.setEntry(node.id, isEntry: value, in: project), name: InterfaceLanguage.label("设置入口"))
    }

    func setIdea(_ node: StoryNode, _ idea: Bool) {
        session.updateNode(node.id) { value in
            value.status = idea ? .idea : .draft
            if idea { value.chapterID = nil }
        }
    }

    func delete(_ node: StoryNode) {
        guard let project = session.project else { return }
        session.apply(ProjectMutations.deleteNode(node.id, in: project), name: InterfaceLanguage.label("删除场景"))
        session.selectedNodeID = nil
    }

    func updateCharacterIDs(_ node: StoryNode, _ ids: [CharacterID]) {
        session.updateNode(node.id) { value in value.characterIDs = ids }
    }

    func updatePlaceIDs(_ node: StoryNode, _ ids: [PlaceID]) {
        session.updateNode(node.id) { value in value.placeIDs = ids }
    }

    func addCharacter(to node: StoryNode) {
        guard let project = session.project else { return }
        let name = newCharacterName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let character = StoryCharacter(name: name)
        var operations = ProjectMutations.appendCharacter(character, to: project)
        operations += ProjectMutations.updateNode(node.id, in: project) { value in
            value.characterIDs.append(character.id)
        }
        session.apply(operations, name: InterfaceLanguage.label("新建人物"))
        newCharacterName = ""
    }

    func addSetting(to node: StoryNode) {
        guard let project = session.project else { return }
        let title = newSettingTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let setting = Setting(title: title, isConfirmed: true, attachedNodeIDs: [node.id])
        var operations = ProjectMutations.appendSetting(setting, to: project)
        operations += ProjectMutations.updateNode(node.id, in: project) { value in
            value.settingIDs.append(setting.id)
        }
        session.apply(operations, name: InterfaceLanguage.label("新建事实设定"))
        newSettingTitle = ""
    }

    func pickImage(for node: StoryNode) {
        session.pickImage(for: node.id)
    }
}
