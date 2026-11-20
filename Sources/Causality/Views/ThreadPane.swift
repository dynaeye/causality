import CausalityCore
import SwiftUI

/// 线索账本：左边线索列表，右边一条跨章的脊柱。
struct ThreadPane: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession

    @State private var showingNewThread = false
    @State private var newThreadName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(theme.border).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                list
                    .frame(width: 260)
                Rectangle().fill(theme.border).frame(width: 1)
                if let thread = session.focusedThread {
                    spine(thread)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(theme.background)
        .alert("新建线索", isPresented: $showingNewThread) {
            TextField("线索名", text: $newThreadName)
            Button("创建") {
                session.addThread(name: newThreadName, kind: .foreshadow)
                newThreadName = ""
            }
            Button("取消", role: .cancel) { newThreadName = "" }
        } message: {
            Text("先建一条伏笔线索，再在脊柱上加减点。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("线索")
                .font(theme.fontTitle)
            Text(String(format: InterfaceLanguage.label("%lld 条"), session.threads.count))
                .font(theme.fontMin)
                .foregroundStyle(theme.textTertiary)
            Spacer()
            Button {
                newThreadName = ""
                showingNewThread = true
            } label: {
                Label("新建线索", systemImage: "plus")
            }
            .controlSize(.small)
            Button {
                session.closeThreads()
            } label: {
                Label("关闭", systemImage: "xmark")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(theme.surface)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if session.threads.isEmpty {
                    Text("还没有线索。")
                        .font(theme.fontMin)
                        .foregroundStyle(theme.textTertiary)
                        .padding(12)
                }
                ForEach(session.threads) { thread in
                    Button {
                        session.focusedThreadID = thread.id
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(threadColor(thread.kind))
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(thread.name)
                                    .font(theme.fontMin)
                                    .foregroundStyle(theme.textPrimary)
                                    .lineLimit(1)
                                Text(LocalizedStringKey(thread.kind.displayName))
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            Spacer(minLength: 2)
                            if thread.isUnpaid {
                                Text("未收")
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(theme.warning.opacity(0.16), in: Capsule())
                                    .foregroundStyle(theme.warning)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            session.focusedThreadID == thread.id ? theme.accentSoft : Color.clear
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text("选一条线索")
                .font(theme.fontCardTitle)
                .foregroundStyle(theme.textPrimary)
            Text("左边还没有线索，或者还没有选中。")
                .font(theme.fontMin)
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func spine(_ thread: StoryThread) -> some View {
        let points = session.project.map { ThreadSpine.points(for: thread, in: $0) } ?? []
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(thread.name)
                    .font(theme.fontCardTitle)
                Picker("类型", selection: Binding(
                    get: { thread.kind },
                    set: { session.setThreadKind(thread.id, kind: $0) }
                )) {
                    ForEach(ThreadKind.allCases, id: \.self) { kind in
                        Text(LocalizedStringKey(kind.displayName)).tag(kind)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 110)
                if thread.isUnpaid {
                    Text("未收")
                        .font(.system(size: 10))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(theme.warning.opacity(0.16), in: Capsule())
                        .foregroundStyle(theme.warning)
                }
                Spacer()
                addPointMenu(thread)
                Button(role: .destructive) {
                    session.deleteThread(thread.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("删除这条线索")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            if !thread.summary.isEmpty {
                Text(thread.summary)
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }

            if points.isEmpty {
                Text("这条线索还没有点。先选中一张卡，再从右上角把它记到线索上。")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
                    .padding(20)
            } else {
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(theme.border)
                            .frame(width: 2)
                            .padding(.leading, 5)
                            .padding(.vertical, 14)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                                if index > 0, points[index - 1].chapterID != point.chapterID {
                                    chapterGap(point.chapterTitle)
                                }
                                pointRow(point, thread: thread)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func chapterGap(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
            HorizontalDashedLine()
                .stroke(theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 1)
        }
        .padding(.vertical, 8)
        .padding(.leading, 18)
    }

    private func pointRow(_ point: ThreadSpinePoint, thread: StoryThread) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(threadColor(thread.kind))
                .frame(width: 12, height: 12)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(point.entry.role.displayName))
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(threadColor(thread.kind).opacity(0.16), in: Capsule())
                        .foregroundStyle(threadColor(thread.kind))
                    Button {
                        session.selectedNodeID = point.node.id
                        session.focusedChapterID = point.chapterID
                        session.closeThreads()
                        session.viewMode = .outline
                    } label: {
                        Text("\(point.chapterTitle) · \(point.node.title)")
                            .font(theme.fontBody)
                            .foregroundStyle(theme.textPrimary)
                    }
                    .buttonStyle(.link)
                }
                TextField("这一笔写什么", text: entryTextBinding(thread: thread, entry: point.entry))
                    .textFieldStyle(.plain)
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer(minLength: 8)

            Button {
                session.removeThreadEntry(thread.id, entryID: point.entry.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("把这一点移出线索")
        }
        .padding(.vertical, 7)
        .padding(.leading, 0)
    }

    private func addPointMenu(_ thread: StoryThread) -> some View {
        Menu {
            ForEach(ThreadRole.allCases, id: \.self) { role in
                Button(LocalizedStringKey(role.displayName)) {
                    guard let nodeID = session.selectedNodeID else { return }
                    session.addThreadEntry(thread.id, nodeID: nodeID, role: role)
                }
            }
        } label: {
            Label("把当前场景记为…", systemImage: "plus")
                .font(theme.fontMin)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(session.selectedNodeID == nil)
        .help(LocalizedStringKey(session.selectedNodeID == nil ? "先选中一张卡" : "把当前场景记到这条线索上"))
    }

    private func entryTextBinding(thread: StoryThread, entry: ThreadEntry) -> Binding<String> {
        Binding(
            get: {
                session.project?.threads
                    .first { $0.id == thread.id }?
                    .entries.first { $0.id == entry.id }?
                    .text ?? ""
            },
            set: { value in
                session.updateThreadEntryText(thread.id, entryID: entry.id, text: value)
            }
        )
    }

    private func threadColor(_ kind: ThreadKind) -> Color {
        switch kind {
        case .foreshadow: theme.accent
        case .theme: theme.choice
        case .arc: theme.ending
        case .quest: theme.warning
        case .reveal: .purple
        }
    }
}


/// 一段虚线，用来表示章节之间的空档。
private struct HorizontalDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
