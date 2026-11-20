import CausalityCore
import SwiftUI

/// 写作模式：中栏一次只放一场。
///
/// 上方是前一场结尾、下方是后一场开头，正文按 740pt 排；右侧一张资料卡，底部把去向内联进来。
/// 顺序走 `chapter.order`，与大纲的 DFS 分开算。
struct WritingPane: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession

    @State private var newEdgeLabel = ""
    @State private var newEdgeCondition = ""

    var body: some View {
        Group {
            if let scene = session.currentWritingScene,
               let node = session.project?.node(scene.id) {
                content(scene: scene, node: node)
            } else {
                emptyState
            }
        }
        .background(theme.background)
    }

    // MARK: 骨架

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text("写作模式")
                .font(theme.fontCardTitle)
                .foregroundStyle(theme.textPrimary)
            Text("这个工程还没有正式场景。先在故事板里写一张卡。")
                .font(theme.fontBody)
                .foregroundStyle(theme.textSecondary)
            HStack(spacing: 8) {
                Button("新建场景") { session.addNode() }
                Button("退出写作") { session.isWriting = false }
            }
            .controlSize(.small)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(scene: WritingScene, node: StoryNode) -> some View {
        VStack(spacing: 0) {
            topBar(scene)
            Rectangle().fill(theme.border).frame(height: 1)
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        context(session.writingNeighbors.previous, label: InterfaceLanguage.label("前一场结尾"), fromEnd: true)
                        editor(node)
                        wordLine(node)
                        context(session.writingNeighbors.next, label: InterfaceLanguage.label("后一场开头"), fromEnd: false)
                        Rectangle()
                            .fill(theme.border)
                            .frame(height: 1)
                            .padding(.top, 6)
                        destinations(node)
                    }
                    .frame(maxWidth: 740)
                    infoCard(node)
                }
                .frame(maxWidth: 1000, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
        }
    }

    private func topBar(_ scene: WritingScene) -> some View {
        let neighbors = session.writingNeighbors
        return HStack(spacing: 12) {
            Button {
                session.stepWriting(-1)
            } label: {
                Label("上一场", systemImage: "chevron.up")
            }
            .disabled(neighbors.previous == nil)

            Button {
                session.stepWriting(1)
            } label: {
                Label("下一场", systemImage: "chevron.down")
            }
            .disabled(neighbors.next == nil)

            Spacer()

            Text(String(format: InterfaceLanguage.label("%@ · 第 %lld 场"), scene.chapterTitle, scene.sceneNumber))
                .font(theme.fontMin)
                .foregroundStyle(theme.textSecondary)

            Spacer()

            Button {
                session.newNextWritingScene()
            } label: {
                Label("新建下一场", systemImage: "plus")
            }
            .help("在当前场后面新建一场（⇧⌘⏎）")

            Button {
                session.forkWritingScene()
            } label: {
                Label("分叉", systemImage: "arrow.triangle.branch")
            }
            .help("从当前场分叉（⇧⌘D）")

            Button {
                session.isWriting = false
            } label: {
                Label("退出写作", systemImage: "xmark")
            }
            .help("退出写作模式（⌘⏎）")
        }
        .controlSize(.small)
        .padding(.horizontal, 22)
        .padding(.vertical, 9)
        .background(theme.surface)
    }

    // MARK: 正文与上下文

    private func editor(_ node: StoryNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("场景标题", text: session.textBinding(node.id, \.title, field: "title"))
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            TextDraftEditor(session: session, field: .nodeBody(node.id), autoFocus: true)
                .font(.system(size: 17))
                .lineSpacing(7)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 380)
                .padding(14)
                .background(theme.surfaceRaised.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.border, lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private func context(_ scene: WritingScene?, label: String, fromEnd: Bool) -> some View {
        if let scene {
            Button {
                session.setWritingScene(scene)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(label) · \(scene.node.title)")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                    Text(excerpt(scene.node.body, fromEnd: fromEnd))
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .foregroundStyle(theme.textSecondary.opacity(0.55))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("跳到这一场")
        }
    }

    private func excerpt(_ body: String, fromEnd: Bool) -> String {
        let lines = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let picked = fromEnd ? Array(lines.suffix(3)) : Array(lines.prefix(3))
        return picked.isEmpty ? InterfaceLanguage.label("（还没有正文）") : picked.joined(separator: "\n")
    }

    private func wordLine(_ node: StoryNode) -> some View {
        let words = session.wordCounts.count(of: node.id)
        return HStack(spacing: 10) {
            Text(String(format: InterfaceLanguage.label("本场 %@"), WordCountText.text(words)))
            if let target = node.targetWords, target > 0 {
                ProgressView(value: Double(words), total: Double(target))
                    .progressViewStyle(.linear)
                    .tint(theme.accent)
                    .frame(width: 120)
                Text(String(format: InterfaceLanguage.label("目标 %@"), WordCountText.text(target)))
            }
            Spacer(minLength: 0)
            if let state = node.writingState {
                Text(LocalizedStringKey(state.displayName))
            }
        }
        .font(theme.fontMin)
        .foregroundStyle(theme.textTertiary)
    }

    // MARK: 资料卡

    private func infoCard(_ node: StoryNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("场景资料")
                .font(theme.fontMinBold)
                .foregroundStyle(theme.textSecondary)

            infoRow("视角", povName(node))
            infoRow("时间", node.storyTimeLabel.isEmpty ? InterfaceLanguage.label("未填") : node.storyTimeLabel)
            infoRow("张力", node.tension.map { "\($0)/5" } ?? InterfaceLanguage.label("未填"))

            Rectangle().fill(theme.border).frame(height: 1)

            infoRow("在场", castNames(node))
            infoRow("线索", InterfaceLanguage.label("未建"))

            Rectangle().fill(theme.border).frame(height: 1)

            infoRow("目标", node.targetWords.map { WordCountText.text($0) } ?? InterfaceLanguage.label("未设"))
            infoRow("字数", WordCountText.text(session.wordCounts.count(of: node.id)))
        }
        .padding(12)
        .frame(width: 220, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(theme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func povName(_ node: StoryNode) -> String {
        guard let id = node.pov,
              let name = session.project?.characters.first(where: { $0.id == id })?.name else {
            return InterfaceLanguage.label("未定")
        }
        return name
    }

    private func castNames(_ node: StoryNode) -> String {
        let index = session.projectIndex
        let names = node.characterIDs.compactMap { index?.characterByID[$0]?.name }
        return names.isEmpty ? InterfaceLanguage.label("未填") : names.joined(separator: InterfaceLanguage.listSeparator)
    }

    // MARK: 去向

    private func destinations(_ node: StoryNode) -> some View {
        let edges = (session.project?.edges ?? []).filter { $0.from == node.id }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("去向")
                    .font(theme.fontMinBold)
                    .foregroundStyle(theme.textSecondary)
                Text("选项写在正文旁边，按回车继续")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
                Spacer()
            }

            if edges.isEmpty {
                Text("还没有去向。选一个场景，把这一场接下去。")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
            }

            ForEach(edges) { edge in
                edgeRow(edge)
            }

            newEdgeRow(node)
        }
    }

    private func edgeRow(_ edge: StoryEdge) -> some View {
        HStack(spacing: 6) {
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
            } label: {
                Text(LocalizedStringKey(edge.kind.displayName))
                    .font(theme.fontMin)
                    .foregroundStyle(theme.lineColor(for: edge.kind))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            TextField("选项文案", text: edgeLabelBinding(edge))
                .textFieldStyle(.roundedBorder)
                .font(theme.fontMin)

            TextField("条件（可空）", text: edgeConditionBinding(edge))
                .textFieldStyle(.roundedBorder)
                .font(theme.fontMin)
                .frame(width: 150)

            Text("→ \(targetTitle(edge))")
                .font(theme.fontMin)
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)

            Button {
                guard let project = session.project else { return }
                session.apply(ProjectMutations.disconnect(edge.id, in: project), name: InterfaceLanguage.label("删除发展线"))
            } label: {
                Image(systemName: "trash")
                    .font(theme.fontMin)
            }
            .buttonStyle(.plain)
            .help("删掉这条去向")
        }
    }

    private func newEdgeRow(_ node: StoryNode) -> some View {
        HStack(spacing: 6) {
            TextField("新选项文案", text: $newEdgeLabel)
                .textFieldStyle(.roundedBorder)
                .font(theme.fontMin)

            TextField("条件（可空）", text: $newEdgeCondition)
                .textFieldStyle(.roundedBorder)
                .font(theme.fontMin)
                .frame(width: 150)

            Menu("接到…") {
                ForEach(candidates(excluding: node.id)) { target in
                    Button("\(target.chapterTitle) · \(target.node.title)") {
                        addEdge(from: node, to: target)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(candidates(excluding: node.id).isEmpty)
        }
    }

    private func candidates(excluding id: NodeID) -> [WritingScene] {
        session.writingScenes.filter { $0.id != id }
    }

    private func addEdge(from node: StoryNode, to target: WritingScene) {
        session.connect(
            from: node.id,
            to: target.id,
            kind: .choice,
            label: newEdgeLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            condition: newEdgeCondition.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        newEdgeLabel = ""
        newEdgeCondition = ""
    }

    private func targetTitle(_ edge: StoryEdge) -> String {
        guard let node = session.project?.node(edge.to) else { return InterfaceLanguage.label("未知") }
        return "\(session.chapterTitle(node.chapterID)) · \(node.title)"
    }

    private func edgeLabelBinding(_ edge: StoryEdge) -> Binding<String> {
        Binding(
            get: { self.session.project?.edge(edge.id)?.label ?? "" },
            set: { value in
                guard let project = self.session.project else { return }
                self.session.apply(
                    ProjectMutations.updateEdge(edge.id, in: project) { $0.label = value },
                    name: InterfaceLanguage.label("修改连线文字"),
                    coalescingKey: "edge:\(edge.id):label"
                )
            }
        )
    }

    private func edgeConditionBinding(_ edge: StoryEdge) -> Binding<String> {
        Binding(
            get: { self.session.project?.edge(edge.id)?.condition ?? "" },
            set: { value in
                guard let project = self.session.project else { return }
                self.session.apply(
                    ProjectMutations.updateEdge(edge.id, in: project) { $0.condition = value },
                    name: InterfaceLanguage.label("修改连线条件"),
                    coalescingKey: "edge:\(edge.id):condition"
                )
            }
        )
    }
}
