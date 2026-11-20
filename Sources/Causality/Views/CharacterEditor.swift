import CausalityCore
import SwiftUI

/// 人物脉络右侧的编辑栏：改名、写简介与备注，看他的出场和因果条目。
struct CharacterEditor: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession
    let characterID: CharacterID
    let onCollapse: () -> Void

    @State private var newRelationKind: RelationKind = .father
    @State private var newRelationTarget: CharacterID?

    private var character: StoryCharacter? {
        session.project?.characters.first { $0.id == characterID }
    }

    private var node: CharacterGraphNode? {
        guard let project = session.project else { return nil }
        return CharacterGraph.build(project: project).nodes.first { $0.id == characterID }
    }

    var body: some View {
        ScrollView {
            content
        }
        .frame(width: 300)
        .clipped()
        .background(theme.surface)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let character {
                header(character)
                field("名字") {
                    TextField("名字", text: binding(character, \.name, field: "name"))
                        .textFieldStyle(.roundedBorder)
                        .font(theme.fontBody)
                }
                field("简介") {
                    TextDraftEditor(session: session, field: .characterSummary(character.id))
                        .font(theme.fontBody)
                        .scrollContentBackground(.hidden)
                        .frame(height: 92)
                        .padding(4)
                        .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(theme.border, lineWidth: 1)
                        }
                }
                field("备注") {
                    TextDraftEditor(session: session, field: .characterNotes(character.id))
                        .font(theme.fontMin)
                        .scrollContentBackground(.hidden)
                        .frame(height: 72)
                        .padding(4)
                        .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(theme.border, lineWidth: 1)
                        }
                }
                relationSection(character)
                sceneList
                linkList
                Spacer(minLength: 0)
                Button("删除这个人物", role: .destructive) {
                    session.deleteCharacter(characterID)
                }
                .buttonStyle(.link)
                .font(theme.fontMin)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ character: StoryCharacter) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: character.name.isEmpty ? InterfaceLanguage.label("未命名人物") : character.name)
                    .font(theme.fontCardTitle)
                    .foregroundStyle(theme.textPrimary)
                Text(node?.hasAppeared == true ? LocalizedStringKey(String(format: InterfaceLanguage.label("出场 %lld 场 · 关系 %lld 条"), node?.sceneCount ?? 0, node?.linkCount ?? 0)) : LocalizedStringKey("还没出场"))
                    .font(theme.fontMin)
                    .foregroundStyle(node?.hasAppeared == true ? theme.textTertiary : theme.warning)
            }
            Spacer(minLength: 0)
            Button(action: onCollapse) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("收回详情")
        }
    }

    private func relationSection(_ character: StoryCharacter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("亲属与亲友")

            ForEach(character.relations) { relation in
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(relation.kind.displayName))
                        .font(theme.fontMin)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.accentSoft, in: Capsule())
                        .foregroundStyle(theme.textPrimary)
                    Text(name(of: relation.target))
                        .font(theme.fontMin)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        session.removeRelation(relation.id, from: characterID)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if otherCharacters.isEmpty {
                Text("还没有别人可以连。先添加人物。")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
            } else {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text("我是对方的")
                            .font(theme.fontMin)
                            .foregroundStyle(theme.textSecondary)
                        Picker("我是对方的", selection: $newRelationKind) {
                            ForEach(RelationKind.allCases, id: \.self) { kind in
                                Text(LocalizedStringKey(kind.displayName)).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 4) {
                        Picker("对象", selection: $newRelationTarget) {
                            Text("选人物").tag(CharacterID?.none)
                            ForEach(otherCharacters) { other in
                                Text(verbatim: other.name.isEmpty ? InterfaceLanguage.label("未命名人物") : other.name)
                                    .tag(CharacterID?.some(other.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                        Button("添加") {
                            guard let target = newRelationTarget else { return }
                            session.addRelation(newRelationKind, from: characterID, to: target)
                            newRelationTarget = nil
                        }
                        .disabled(newRelationTarget == nil)
                    }
                }
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)

                if let target = newRelationTarget {
                    Text(relationPreview(target))
                        .font(theme.fontMin)
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(2)
                }
            }
        }
    }

    /// 把选择读成一句人话，避免「母亲」到底指谁的母亲这种歧义。
    private func relationPreview(_ target: CharacterID) -> String {
        let me = session.project?.characters.first { $0.id == characterID }?.name ?? "?"
        let other = name(of: target)
        switch newRelationKind {
        case .spouse: return String(format: InterfaceLanguage.label("%@ 与 %@ 是夫妻"), me, other)
        case .lover: return String(format: InterfaceLanguage.label("%@ 与 %@ 是恋人"), me, other)
        case .friend: return String(format: InterfaceLanguage.label("%@ 与 %@ 是朋友"), me, other)
        case .sibling: return String(format: InterfaceLanguage.label("%@ 与 %@ 是兄弟姐妹"), me, other)
        case .rival: return String(format: InterfaceLanguage.label("%@ 与 %@ 是对手"), me, other)
        case .enemy: return String(format: InterfaceLanguage.label("%@ 与 %@ 是仇敌"), me, other)
        case .other:
            return String(
                format: InterfaceLanguage.label("%@ 与 %@ 是 %@ 的关联人（其他）"),
                me, other, other
            )
        default:
            return String(
                format: InterfaceLanguage.label("%@ 是 %@ 的%@"),
                me, other, InterfaceLanguage.label(newRelationKind.displayName)
            )
        }
    }

    private var otherCharacters: [StoryCharacter] {
        guard let project = session.project else { return [] }
        return project.characters.filter { $0.id != characterID }
    }

    private func name(of id: CharacterID) -> String {
        guard let character = session.project?.characters.first(where: { $0.id == id }) else { return "?" }
        return character.name.isEmpty ? InterfaceLanguage.label("未命名人物") : character.name
    }

    private var sceneList: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("出场场景")
            if let node, !node.sceneIDs.isEmpty, let project = session.project {
                ForEach(node.sceneIDs, id: \.self) { sceneID in
                    if let scene = project.node(sceneID) {
                        Button {
                            session.selectedNodeID = scene.id
                            session.detailMode = .inspector
                        } label: {
                            Text(scene.title)
                                .font(theme.fontMin)
                                .foregroundStyle(theme.textSecondary)
                        }
                        .buttonStyle(.link)
                    }
                }
            } else {
                Text("还没在任何场景里出场，先不连因果线。")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private var linkList: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("因果条目")
            let links = currentLinks
            if links.isEmpty {
                Text("还没有跨人物的因果线。")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
            } else {
                ForEach(links) { link in
                    Text(verbatim: String(
                        format: InterfaceLanguage.label("%@：%@"),
                        InterfaceLanguage.label(link.kind.displayName),
                        link.label
                    ))
                        .font(theme.fontMin)
                        .foregroundStyle(theme.lineColor(for: link.kind))
                        .lineLimit(2)
                }
            }
        }
    }

    private var currentLinks: [CharacterGraphLink] {
        guard let project = session.project else { return [] }
        let graph = CharacterGraph.build(project: project)
        return graph.links.filter { $0.from == characterID || $0.to == characterID }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            fieldLabel(title)
            content()
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(theme.fontMin)
            .foregroundStyle(theme.textSecondary)
    }

    private func binding(
        _ character: StoryCharacter,
        _ keyPath: WritableKeyPath<StoryCharacter, String>,
        field: String
    ) -> Binding<String> {
        Binding(
            get: { self.session.project?.characters.first { $0.id == characterID }?[keyPath: keyPath] ?? "" },
            set: { newValue in
                self.session.updateCharacter(characterID, coalescingKey: "character:\(characterID):\(field)") { value in
                    value[keyPath: keyPath] = newValue
                }
            }
        )
    }
}
