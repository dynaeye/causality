import CausalityCore
import SwiftUI
import UniformTypeIdentifiers

/// 故事板：一章一列，卡片从上到下按作者编排，缝隙可以插卡、也可以落卡。
struct StoryboardPane: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession
    /// 右栏浮层的宽度：最后一列要能滚到浮层左边，否则永远藏在面板底下。
    var inspectorWidth: CGFloat = 0

    @State private var editingGap: GapKey?
    @State private var dropTarget: GapKey?
    @State private var draggingCard: NodeID?
    @State private var draggingPoint: CGPoint = .zero
    @State private var gapFrames: [GapKey: CGRect] = [:]
    @State private var columnFrames: [ChapterID: CGRect] = [:]
    @State private var draftTitle: String = ""
    @State private var chapterPendingDelete: Chapter?
    /// 拖动空白处平移：记下按下时的滚动位置，拖动量按差量换算。
    @State private var scrollPosition = ScrollPosition(idType: Never.self)
    @State private var panAnchor: CGPoint?

    private let columnWidth: CGFloat = 336

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(session.project?.chapters ?? []) { chapter in
                        column(for: chapter)
                            .id(chapter.id)
                    }
                    newChapterColumn
                }
                // 按住空白处拖动平移：卡片自带拖动是子视图手势，优先接走，
                // 落在列内空白或列间缝里才落到这一层。
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named("storyboard"))
                        .onChanged { value in
                            if panAnchor == nil {
                                panAnchor = scrollPosition.point ?? .zero
                            }
                            guard let anchor = panAnchor else { return }
                            scrollPosition.scrollTo(
                                x: anchor.x - value.translation.width,
                                y: anchor.y - value.translation.height
                            )
                        }
                        .onEnded { _ in panAnchor = nil }
                )
                .padding(.leading, 16)
                .padding(.trailing, 16 + inspectorWidth)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.visible)
            .scrollPosition($scrollPosition)
            // 一章一列：鼠标滚轮只能上下，横向点侧栏章节名，或按住空白处拖。
            // 用 task(id:) 而不是 onAppear：既盖住首次进入，也盖住切换章节，
            // 而且等布局量过一次再滚，否则 scrollTo 会被截在半路。
            .task(id: session.focusedChapterID) {
                guard let chapterID = session.focusedChapterID else { return }
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeInOut(duration: 0.18)) {
                    scrollPosition.scrollTo(id: chapterID, anchor: .leading)
                }
            }
        .background(theme.background)
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .named("storyboard"))
                .onEnded { value in
                    let insideColumn = columnFrames.contains { $0.value.contains(value.location) }
                    if !insideColumn {
                        session.selectedNodeID = nil
                    }
                }
        )
        .coordinateSpace(name: "storyboard")
        .onPreferenceChange(GapFramesPreference.self) { gapFrames = $0 }
        .onPreferenceChange(ColumnFramesPreference.self) { columnFrames = $0 }
        .onChange(of: session.insertion) { _, newValue in
            if let newValue {
                editingGap = GapKey(chapterID: newValue.chapterID, index: newValue.index)
            }
        }
        .alert(
            "删除本章？",
            isPresented: Binding(
                get: { chapterPendingDelete != nil },
                set: { if !$0 { chapterPendingDelete = nil } }
            ),
            presenting: chapterPendingDelete
        ) { chapter in
            Button("删除", role: .destructive) {
                chapterPendingDelete = nil
                guard let project = session.project else { return }
                session.apply(ProjectMutations.deleteChapter(chapter.id, in: project), name: InterfaceLanguage.label("删除章节"))
            }
            Button("取消", role: .cancel) { chapterPendingDelete = nil }
        } message: { chapter in
            let count = session.cards(in: chapter.id).count
            Text(String(format: InterfaceLanguage.label("「%@」和里面的 %lld 张卡会一起删除，可以撤销。"), chapter.title, count))
        }
    }

    // MARK: 列

    private func column(for chapter: Chapter) -> some View {
        let chapterIndex = (session.project?.chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0) + 1
        let cards = session.cards(in: chapter.id)
        let groups = session.project.map { AlternateGroups.compute(chapter: chapter, project: $0) } ?? []
        let forkGroups = Dictionary(uniqueKeysWithValues: groups.map { ($0.forkNodeID, $0) })
        let collapsed = groups.filter { session.collapsedAlternateGroups.contains($0.forkNodeID) }
        let hidden = Set(collapsed.flatMap(\.memberNodeIDs))
        var memberGroup: [NodeID: (AlternateGroup, Int)] = [:]
        var closeGroups: [NodeID: AlternateGroup] = [:]
        for group in groups {
            for member in group.memberNodeIDs {
                if let branch = group.branchByNode[member] {
                    memberGroup[member] = (group, branch)
                }
            }
            if let close = group.closeNodeID {
                closeGroups[close] = group
            }
        }

        return VStack(alignment: .leading, spacing: 0) {
            header(chapter: chapter, index: chapterIndex, count: cards.count)
            VStack(spacing: 0) {
                gap(chapterID: chapter.id, index: 0)
                ForEach(Array(cards.enumerated()), id: \.element.id) { offset, node in
                    if !hidden.contains(node.id) {
                        card(
                            node,
                            chapterID: chapter.id,
                            forkGroup: forkGroups[node.id],
                            member: memberGroup[node.id],
                            closeGroup: closeGroups[node.id]
                        )
                        if let group = forkGroups[node.id], hidden.contains(where: { group.memberNodeIDs.contains($0) }) {
                            collapsedGroupCard(group)
                        }
                        gap(chapterID: chapter.id, index: offset + 1)
                    }
                }
                addCardButton(chapterID: chapter.id, index: cards.count)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(width: columnWidth)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ColumnFramesPreference.self,
                    value: [chapter.id: proxy.frame(in: .named("storyboard"))]
                )
            }
        )
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.border, lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            crossChapterBadges(for: chapter)
                .padding(.top, 42)
                .offset(x: 8)
        }
    }

    /// 列右缘的跨章出口：从这一章的某张卡出发，落到另一章。
    @ViewBuilder
    private func crossChapterBadges(for chapter: Chapter) -> some View {
        let exits = crossChapterExits(for: chapter)
        if !exits.isEmpty {
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(exits.prefix(3)) { exit in
                    Button {
                        session.selectedNodeID = exit.to.id
                        session.focusedChapterID = exit.to.chapterID
                    } label: {
                        HStack(spacing: 3) {
                            Text(exit.from.title)
                                .lineLimit(1)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8, weight: .semibold))
                            Text(exit.chapterTitle)
                                .lineLimit(1)
                        }
                        .font(.system(size: 9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(theme.accentSoft, in: Capsule())
                        .foregroundStyle(theme.textSecondary)
                        .overlay {
                            Capsule().strokeBorder(theme.accent.opacity(0.25), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(String(format: InterfaceLanguage.label("跨章出口：%@ → %@"), exit.from.title, exit.to.title))
                }
                if exits.count > 3 {
                    Text(String(format: InterfaceLanguage.label("+%lld 条跨章"), exits.count - 3))
                        .font(.system(size: 9))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    private struct CrossChapterExit: Identifiable {
        let id: String
        let from: StoryNode
        let to: StoryNode
        let chapterTitle: String
    }

    private func crossChapterExits(for chapter: Chapter) -> [CrossChapterExit] {
        guard let project = session.project else { return [] }
        var exits: [CrossChapterExit] = []
        var seen: Set<String> = []
        for edge in project.edges {
            guard let from = project.node(edge.from), from.chapterID == chapter.id,
                  let to = project.node(edge.to), let targetChapter = to.chapterID,
                  targetChapter != chapter.id,
                  seen.insert(edge.from.rawValue.uuidString + "->" + edge.to.rawValue.uuidString).inserted else {
                continue
            }
            exits.append(CrossChapterExit(
                id: edge.id.rawValue.uuidString,
                from: from,
                to: to,
                chapterTitle: project.chapter(targetChapter)?.title ?? InterfaceLanguage.label("另一章")
            ))
        }
        return exits
    }

    private func header(chapter: Chapter, index: Int, count: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 18, height: 18)
                .background(theme.border.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
            // 章节标题允许两行，统计行单独占一行，列宽 336 pt 下英文也不会截断。
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .font(theme.fontCardTitle)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(format: InterfaceLanguage.label("%lld 张 · %@"), count, WordCountText.text(session.wordCounts.count(of: chapter.id))))
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .help("卡数含灵感卡；字数只算正式场景。")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("在末尾插一张卡") {
                    session.setInsertion(
                        CardInsertionPoint(chapterID: chapter.id, index: count, anchorNodeID: count > 0 ? session.cards(in: chapter.id).last?.id : nil)
                    )
                }
                Button("新建章节") { session.addChapter() }
                Divider()
                Button("删除本章", role: .destructive) {
                    chapterPendingDelete = chapter
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
        }
    }

    // MARK: 卡片与缝隙

    private func card(
        _ node: StoryNode,
        chapterID: ChapterID,
        forkGroup: AlternateGroup?,
        member: (AlternateGroup, Int)?,
        closeGroup: AlternateGroup?
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if let member {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(branchColor(member.1))
                    .frame(width: 4)
                    .padding(.vertical, 6)
                    .padding(.leading, 2)
            }
            StoryboardCardView(session: session, node: node)
                .padding(.leading, member == nil ? 0 : 6)
                .overlay(alignment: .topLeading) {
                    if let member {
                        Text("\(member.1 + 1)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(branchColor(member.1), in: Circle())
                            .offset(x: -8, y: -8)
                            .help(String(format: InterfaceLanguage.label("第 %lld 条分支"), member.1 + 1))
                    }
                    if closeGroup != nil {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(theme.textTertiary)
                            .offset(x: -14, y: 18)
                            .help("并列组在这里汇合")
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let forkGroup {
                        Button {
                            toggleAlternateGroup(forkGroup)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 8))
                                Text("\(forkGroup.branchCount)")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(theme.accentSoft, in: Capsule())
                            .foregroundStyle(theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 8, y: 10)
                        .help("并列组：点一下折叠 / 展开")
                    }
                }
        }
        .padding(.vertical, 4)
        .opacity(draggingCard == node.id ? 0.55 : 1)
        .gesture(cardDrag(for: node))
    }

    private func branchColor(_ index: Int) -> Color {
        index % 2 == 0 ? theme.accent : theme.choice
    }

    private func toggleAlternateGroup(_ group: AlternateGroup) {
        if session.collapsedAlternateGroups.contains(group.forkNodeID) {
            session.collapsedAlternateGroups.remove(group.forkNodeID)
        } else {
            session.collapsedAlternateGroups.insert(group.forkNodeID)
        }
    }

    private func collapsedGroupCard(_ group: AlternateGroup) -> some View {
        let titles = group.branchNodeIDs
            .compactMap { session.project?.node($0)?.title }
            .joined(separator: " / ")
        return Button {
            toggleAlternateGroup(group)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.split.2x1")
                Text(String(format: InterfaceLanguage.label("选项 %lld · %@"), group.branchCount, titles))
                    .lineLimit(1)
                Spacer()
                Text("展开")
            }
            .font(theme.fontMin)
            .foregroundStyle(theme.textSecondary)
            .padding(9)
            .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.accent.opacity(0.25), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    /// 自己实现拖拽：手势 + 缝隙命中，不依赖系统拖放会话。
    private func cardDrag(for node: StoryNode) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("storyboard"))
            .onChanged { value in
                if draggingCard != node.id {
                    draggingCard = node.id
                    session.selectedNodeID = node.id
                    session.insertion = nil
                }
                draggingPoint = value.location
                dropTarget = targetGap(for: value.location)
            }
            .onEnded { value in
                defer {
                    draggingCard = nil
                    dropTarget = nil
                }
                guard let key = targetGap(for: value.location) else { return }
                let index = adjustedDropIndex(key.chapterID, key.index, moving: node.id)
                session.moveCard(node.id, to: key.chapterID, at: index)
            }
    }

    /// 光标落在哪一列的哪一处缝隙。
    private func targetGap(for point: CGPoint) -> GapKey? {
        guard let chapterID = columnFrames.first(where: { $0.value.contains(point) })?.key else {
            return nil
        }
        let candidates = gapFrames.filter { $0.key.chapterID == chapterID }
        return candidates.min {
            abs($0.value.midY - point.y) < abs($1.value.midY - point.y)
        }?.key
    }

    @ViewBuilder
    private func gap(chapterID: ChapterID, index: Int) -> some View {
        let key = GapKey(chapterID: chapterID, index: index)
        if editingGap == key {
            gapInput(chapterID: chapterID, index: index)
        } else {
            InsertionGap(
                isActive: session.insertion == CardInsertionPoint(
                    chapterID: chapterID,
                    index: index,
                    anchorNodeID: anchor(chapterID: chapterID, index: index)
                ),
                isTargeted: dropTarget == key,
                onInsert: {
                    editingGap = key
                    draftTitle = ""
                    session.setInsertion(
                        CardInsertionPoint(
                            chapterID: chapterID,
                            index: index,
                            anchorNodeID: anchor(chapterID: chapterID, index: index)
                        )
                    )
                }
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: GapFramesPreference.self,
                        value: [key: proxy.frame(in: .named("storyboard"))]
                    )
                }
            )
        }
    }

    private func gapInput(chapterID: ChapterID, index: Int) -> some View {
        VStack(spacing: 6) {
            TextField("写一句念头，或先放一张图", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
                .font(theme.fontBody)
                .onSubmit { commitInsertion(chapterID: chapterID, index: index) }
            HStack(spacing: 8) {
                Button("插入") { commitInsertion(chapterID: chapterID, index: index) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("放一张图…") { insertWithImage(chapterID: chapterID, index: index) }
                    .controlSize(.small)
                Spacer()
                Button("取消") {
                    editingGap = nil
                    session.insertion = nil
                }
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 4)
    }

    private func commitInsertion(chapterID: ChapterID, index: Int) {
        let point = CardInsertionPoint(
            chapterID: chapterID,
            index: index,
            anchorNodeID: anchor(chapterID: chapterID, index: index)
        )
        session.insertCard(at: point, title: draftTitle)
        editingGap = nil
        draftTitle = ""
    }

    private func insertWithImage(chapterID: ChapterID, index: Int) {
        let point = CardInsertionPoint(
            chapterID: chapterID,
            index: index,
            anchorNodeID: anchor(chapterID: chapterID, index: index)
        )
        session.insertCardWithImage(at: point, title: draftTitle)
        editingGap = nil
        draftTitle = ""
    }

    private func addCardButton(chapterID: ChapterID, index: Int) -> some View {
        Button {
            editingGap = GapKey(chapterID: chapterID, index: index)
            draftTitle = ""
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(theme.fontMinBold)
                Text("插一张卡")
                    .font(theme.fontMin)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    private func anchor(chapterID: ChapterID, index: Int) -> NodeID? {
        let cards = session.cards(in: chapterID)
        guard index > 0, index <= cards.count else { return nil }
        return cards[index - 1].id
    }

    /// 从同一列往下拖时，落点要跳过自己被移走后的位移。
    private func adjustedDropIndex(_ chapterID: ChapterID, _ index: Int, moving id: NodeID) -> Int {
        let current = session.cards(in: chapterID).firstIndex { $0.id == id }
        return ProjectMutations.dropIndex(currentIndex: current, gapIndex: index)
    }

    private var newChapterColumn: some View {
        Button {
            session.addChapter()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .light))
                Text("新建章节")
                    .font(theme.fontMin)
            }
            .foregroundStyle(theme.textSecondary)
            .frame(width: 120, height: 120)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(theme.borderStrong)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 44)
    }
}

struct GapKey: Hashable {
    var chapterID: ChapterID
    var index: Int
}

/// 两张卡之间的落点与插卡入口。
struct InsertionGap: View {
    @Environment(\.theme) private var theme
    let isActive: Bool
    let isTargeted: Bool
    let onInsert: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.clear)
                .frame(height: 16)
            if isHovering || isTargeted || isActive {
                Rectangle()
                    .fill(isTargeted ? theme.accent : theme.borderStrong)
                    .frame(height: isTargeted ? 2 : 1)
                    .padding(.horizontal, 4)
                Button(action: onInsert) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .background(theme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .help("在这里插一张卡")
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

/// 每处缝隙在故事板坐标里的位置，用于拖拽命中。
struct GapFramesPreference: PreferenceKey {
    static let defaultValue: [GapKey: CGRect] = [:]

    static func reduce(value: inout [GapKey: CGRect], nextValue: () -> [GapKey: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ColumnFramesPreference: PreferenceKey {
    static let defaultValue: [ChapterID: CGRect] = [:]

    static func reduce(value: inout [ChapterID: CGRect], nextValue: () -> [ChapterID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
