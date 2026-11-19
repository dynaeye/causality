import CausalityCore
import SwiftUI

/// 思维导图：只画人物。左栏是全部人物，中间是脉络，选中人物后右侧可编辑。
struct MindMapPane: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession
    /// 右栏浮层的宽度：人物编辑卡要让开它。
    var inspectorWidth: CGFloat = 0
    @AppStorage("causal.peopleMode") private var peopleModeRaw = "matrix"


    private var graph: CharacterGraph {
        guard let project = session.project else {
            return CharacterGraph(nodes: [], links: [])
        }
        return CharacterGraph.build(project: project)
    }

    var body: some View {
        HStack(spacing: 0) {
            characterList
                .frame(width: 236)
            Divider().overlay(theme.border)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Picker("人物视图", selection: $peopleModeRaw) {
                        Text("矩阵").tag("matrix")
                        Text("关系").tag("graph")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Text(peopleModeRaw == "matrix" ? LocalizedStringKey("人物 × 章节") : LocalizedStringKey("同场共现实线 · 因果虚线"))
                        .font(theme.fontMin)
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(theme.surface)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.border).frame(height: 1)
                }

                if peopleModeRaw == "matrix" {
                    CharacterMatrixView(
                        session: session,
                        matrix: CharacterMatrixBuilder.build(
                            project: session.project ?? StoryProject(title: "未命名项目")
                        )
                    )
                } else {
                    MindMapGraphView(
                        session: session,
                        graph: graph,
                        inspectorWidth: inspectorWidth,
                        focused: $session.focusedCharacterID
                    )
                }
            }
            .overlay(alignment: .trailing) {
                if let id = session.focusedCharacterID,
                   graph.nodes.contains(where: { $0.id == id }) {
                    CharacterEditor(
                        session: session,
                        characterID: id,
                        onCollapse: { session.focusedCharacterID = nil }
                    )
                    .frame(width: 300)
                    .background(theme.background)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(theme.border).frame(width: 1)
                    }
                    .padding(.trailing, inspectorWidth)
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .background(theme.background)
    }

    // MARK: 人物列表

    private var characterList: some View {
        VStack(alignment: .leading, spacing: 0) {
            listHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(graph.nodes) { node in
                        characterRow(node)
                    }
                    if graph.nodes.isEmpty {
                        Text("还没有人物。点右上角的 + 添加，或在场景详情里加人物。")
                            .font(theme.fontMin)
                            .foregroundStyle(theme.textSecondary)
                            .padding(14)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .background(theme.deep)
        .overlay(alignment: .leading) {
            // 侧栏与人物栏都是 deep，不给一条竖线就会连成一片。
            Rectangle().fill(theme.border).frame(width: 1)
        }
    }

    /// 与大纲的章节头一套：标题 + 一行说明 + 下面一条横线。
    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("人物")
                        .font(theme.fontTitle)
                        .foregroundStyle(theme.textPrimary)
                    Text("\(graph.nodes.count) 人 · 同场 \(graph.coPresenceLinks.count) 条 · 因果 \(graph.links.count) 条")
                        .font(theme.fontMin)
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer(minLength: 4)
                Button {
                    session.focusedCharacterID = session.addCharacter()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("添加一个还没出场的人物")
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
        }
    }

    private func characterRow(_ node: CharacterGraphNode) -> some View {
        Button {
            session.focusedCharacterID = session.focusedCharacterID == node.id ? nil : node.id
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(node.hasAppeared ? theme.accent : theme.borderStrong)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: node.character.name.isEmpty ? InterfaceLanguage.label("未命名人物") : node.character.name)
                        .font(theme.fontBody)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text(node.hasAppeared ? LocalizedStringKey("出场 \(node.sceneCount) 场 · 关系 \(node.linkCount) 条") : LocalizedStringKey("还没出场"))
                        .font(theme.fontMin)
                        .foregroundStyle(node.hasAppeared ? theme.textTertiary : theme.warning)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(session.focusedCharacterID == node.id ? theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
