import CausalityCore
import SwiftUI

struct OutlinePane: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession
    /// 右栏浮层的宽度：正文留出这一段，最后几行不会被浮层盖住。
    var inspectorWidth: CGFloat = 0
    /// 拖动排序时落在哪一行上，用来画插入线。
    @State private var dropTarget: NodeID?

    var body: some View {
        VStack(spacing: 0) {
            routeBar
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleOutlines) { outline in
                        chapterHeader(outline)
                        if !session.isCollapsed(outline.chapterID) {
                            ForEach(outline.rows) { row in
                                rowView(row, chapterID: outline.chapterID)
                                    .id(rowKey(chapterID: outline.chapterID, row: row))
                            }
                        }
                        Rectangle()
                            .fill(theme.border)
                            .frame(height: 1)
                            .padding(.vertical, 6)
                    }
                    if visibleOutlines.isEmpty {
                        Text("还没有章节。用工具栏的 + 新建场景，或在侧栏新建章节。")
                            .foregroundStyle(.secondary)
                            .padding(24)
                    }
                }
                .padding(.vertical, 10)
                .padding(.trailing, inspectorWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: session.selectedNodeID) { _, newNodeID in
                guard let newNodeID,
                      let row = visibleOutlines
                          .flatMap(\.rows)
                          .first(where: { $0.nodeID == newNodeID }),
                      let outline = visibleOutlines.first(where: { $0.rows.contains(row) })
                else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(rowKey(chapterID: outline.chapterID, row: row), anchor: .center)
                }
            }
            }
        }
    }

    /// 顶部的路线筛选：全部 / 只看通往某个结局。
    private var routeBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("全部") { session.routeEndingID = nil }
                ForEach(session.endings) { ending in
                    Button(ending.title) { session.routeEndingID = ending.id }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.system(size: 11))
                    Text(routeLabel)
                        .font(.system(size: 12))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(session.endings.isEmpty)
            .help(session.endings.isEmpty ? "还没有结局卡" : "只看通往某个结局的路径")

            if let route = session.activeRoute {
                Text("路上 \(route.nodeIDs.count) 张 · \(WordCountText.text(session.wordCounts.count(of: route)))")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }

    private var routeLabel: String {
        guard let id = session.routeEndingID,
              let ending = session.project?.node(id) else { return InterfaceLanguage.label("全部路径") }
        return String(format: InterfaceLanguage.label("通往「%@」"), ending.title)
    }

    private var visibleOutlines: [ChapterOutline] {
        let outlines = session.displayedOutlines
        guard let focused = session.focusedChapterID,
              outlines.contains(where: { $0.chapterID == focused }) else {
            return outlines
        }
        return outlines
    }

    private func rowKey(chapterID: ChapterID, row: OutlineRow) -> String {
        "\(chapterID.rawValue.uuidString)-\(row.id)"
    }

    private func chapterHeader(_ outline: ChapterOutline) -> some View {
        let collapsed = session.isCollapsed(outline.chapterID)
        return Button {
            session.toggleChapterCollapse(outline.chapterID)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                    Text(outline.chapterTitle)
                        .font(theme.fontTitle)
                        .foregroundStyle(theme.textPrimary)
                }
                statsRow(outline)
                    .padding(.leading, 17)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func statsRow(_ outline: ChapterOutline) -> some View {
        HStack(spacing: 8) {
            Text("场景 \(outline.sceneCount)")
            Text("字数 \(WordCountText.bare(session.wordCounts.count(of: outline.chapterID)))")
            if outline.revisitCount > 0 {
                Text("汇合跳转 \(outline.revisitCount)")
            }
            if outline.crossChapterCount > 0 {
                Text("跨章 \(outline.crossChapterCount)")
            }
            if outline.detachedCount > 0 {
                Text("未接线 \(outline.detachedCount)")
                    .foregroundStyle(.orange)
            }
        }
        .font(theme.fontMin)
        .foregroundStyle(theme.textTertiary)
    }

    /// 拖动排序：把源卡插到目标卡之前。同一章走顺序表，跨章连章一起搬。
    private func handleDrop(_ items: [String], onto row: OutlineRow, chapterID: ChapterID) -> Bool {
        dropTarget = nil
        guard let raw = items.first, let uuid = UUID(uuidString: raw) else { return false }
        let moving = NodeID(rawValue: uuid)
        guard moving != row.nodeID,
              let project = session.project,
              let targetIndex = project.chapter(chapterID)?.order.firstIndex(of: row.nodeID) else { return false }
        session.moveCard(moving, to: chapterID, at: targetIndex)
        return true
    }

    private func rowView(_ row: OutlineRow, chapterID: ChapterID) -> some View {
        let isSelected = session.selectedNodeID == row.nodeID
        let indent = CGFloat(row.indent) * 18
        let onMainline = session.mainline.contains(node: row.nodeID)
        let isBranch = row.role == .scene && !onMainline && !session.mainline.isEmpty
        return Button {
            session.selectedNodeID = row.nodeID
            if let targetChapter = row.targetChapterID {
                session.focusedChapterID = targetChapter
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                // 主线：左侧一道 accent 竖条；支线：留空。
                Rectangle()
                    .fill(onMainline ? theme.accent : Color.clear)
                    .frame(width: 3)
                    .padding(.leading, indent)
                indicator(for: row)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.nodeTitle)
                            .font(.system(size: 13, weight: row.role == .scene ? .medium : .regular))
                            .foregroundStyle(row.role == .scene ? theme.textPrimary : theme.textSecondary)
                            .lineLimit(1)
                        if row.role == .scene {
                            KindBadge(kind: row.nodeKind)
                            Text(WordCountText.text(session.wordCounts.count(of: row.nodeID)))
                                .font(.system(size: 10))
                                .foregroundStyle(theme.textTertiary)
                                .monospacedDigit()
                        }
                        if isBranch {
                            Text("支线")
                                .font(theme.fontMin)
                                .padding(.horizontal, 4)
                                .background(theme.border.opacity(0.5), in: Capsule())
                                .foregroundStyle(theme.textTertiary)
                        }
                        if row.role == .crossChapter {
                            Text("跨章 → \(session.chapterTitle(row.targetChapterID))")
                                .font(theme.fontMin)
                                .padding(.horizontal, 4)
                                .background(.quaternary, in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let incoming = row.incoming {
                        Text(verbatim: incoming.displayText(localize: InterfaceLanguage.current.label))
                            .font(theme.fontMin)
                            .foregroundStyle(theme.lineColor(for: incoming.kind))
                            .lineLimit(2)
                    }
                    if row.origin == .detached {
                        Text("尚未接入故事")
                            .font(theme.fontMin)
                            .foregroundStyle(theme.warning)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.trailing, 16)
            .background(isSelected ? theme.accentSoft : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(row.nodeID.rawValue.uuidString)
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items, onto: row, chapterID: chapterID)
        } isTargeted: { targeted in
            if targeted {
                dropTarget = row.nodeID
            } else if dropTarget == row.nodeID {
                dropTarget = nil
            }
        }
        .overlay(alignment: .top) {
            if dropTarget == row.nodeID {
                Rectangle()
                    .fill(theme.accent)
                    .frame(height: 2)
            }
        }
        .contextMenu {
            Button("选中") { session.selectedNodeID = row.nodeID }
            ReachableEndingsMenu(session: session, nodeID: row.nodeID)
            Button("删除场景", role: .destructive) {
                guard let project = session.project, let node = project.node(row.nodeID) else { return }
                session.apply(ProjectMutations.deleteNode(node.id, in: project), name: "删除场景")
            }
        }
    }


    private func sceneSymbol(for kind: NodeKind) -> String {
        switch kind {
        case .ending: "flag.checkered"
        case .choice: "arrow.triangle.branch"
        case .event: "circle.fill"
        }
    }

    @ViewBuilder
    private func indicator(for row: OutlineRow) -> some View {
        switch row.role {
        case .scene:
            Image(systemName: sceneSymbol(for: row.nodeKind))
                .font(.system(size: row.nodeKind == .event ? 5 : 10))
                .foregroundStyle(.secondary)
                .frame(width: 12)
        case .revisit:
            Image(systemName: "arrow.uturn.left")
                .font(theme.fontMin)
                .foregroundStyle(.secondary)
                .frame(width: 12)
        case .crossChapter:
            Image(systemName: "arrow.right.to.line")
                .font(theme.fontMin)
                .foregroundStyle(.secondary)
                .frame(width: 12)
        }
    }
}
