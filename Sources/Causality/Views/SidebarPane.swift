import CausalityCore
import SwiftUI

struct SidebarPane: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession

    private var project: StoryProject? { session.project }

    var body: some View {
        VStack(spacing: 0) {
            brandHeader
            ScrollView {
                if !session.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    SearchResultsList(session: session, results: session.searchResults)
                } else {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        chapterSection
                        ideaSection
                        settingSection
                        threadSection
                        auditSection
                    }
                    .padding(.vertical, 8)
                }
            }
            totalsFooter
        }
        .background(theme.deep)
    }

    /// 侧栏底的一行总账：全书字数与场景数。四级里最上面的一级。
    private var totalsFooter: some View {
        let counts = session.wordCounts
        return HStack(spacing: 5) {
            Text("全书 \(WordCountText.text(counts.total))")
            Text("·")
            if counts.finalCount > 0 {
                Text("定稿 \(counts.finalCount)/\(counts.sceneCount)")
            } else {
                Text("\(counts.sceneCount) 场")
            }
            Spacer(minLength: 0)
        }
        .font(theme.fontMin)
        .foregroundStyle(theme.textTertiary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
        .help("全书字数只算正式场景；中文按字、英文按词，标点与空白不计。")
    }

    /// 侧栏顶部的题名「因果 / 一念起，万象生」。居中排列，不跟列表滚。
    private var brandHeader: some View {
        VStack(spacing: 9) {
            BrandWordmark(size: 24)
                .foregroundStyle(theme.textPrimary)
            Rectangle()
                .fill(theme.textTertiary.opacity(0.45))
                .frame(width: 40, height: 1)
            Text("一念起，万象生。")
                .font(.system(size: 12))
                .tracking(0.6)
                .padding(.leading, 0.6)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    private var chapterSection: some View {
        Group {
            sectionHeader("章节", trailing: {
                Button {
                    session.addChapter()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("新建章节")
            })

            ForEach(project?.chapters ?? []) { chapter in
                let count = session.cards(in: chapter.id).count
                Button {
                    session.focusedChapterID = chapter.id
                    if session.viewMode == .outline,
                       let first = session.outlines.first(where: { $0.chapterID == chapter.id })?.rows.first {
                        session.selectedNodeID = first.nodeID
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed")
                            .font(theme.fontMin)
                        Text(chapter.title)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(count)")
                            .font(theme.fontMin)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        session.focusedChapterID == chapter.id
                            ? theme.accentSoft
                            : Color.clear
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var ideaSection: some View {
        Group {
            let ideas = (project?.nodes ?? []).filter { $0.status == .idea }
            if !ideas.isEmpty {
                sectionHeader("灵感卡", topPadding: 14, trailing: {
                    Button {
                        session.addIdeaCard()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                })
                ForEach(ideas) { idea in
                    Button {
                        session.selectedNodeID = idea.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb")
                                .font(theme.fontMin)
                                .foregroundStyle(.secondary)
                            Text(verbatim: idea.title.isEmpty ? InterfaceLanguage.label("未命名灵感") : idea.title)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            session.selectedNodeID == idea.id
                                ? theme.accentSoft
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                sectionHeader("灵感卡", topPadding: 14, trailing: {
                    Button {
                        session.addIdeaCard()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                })
                Text("还没有灵感卡")
                    .font(theme.fontMin)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
    }

    private var settingSection: some View {
        Group {
            let settings = project?.settings ?? []
            if !settings.isEmpty {
                sectionHeader("事实设定", topPadding: 14, trailing: { EmptyView() })
                ForEach(settings) { setting in
                    Button {
                        if let node = setting.attachedNodeIDs.first {
                            session.selectedNodeID = node
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: settingIconName(setting))
                                .font(theme.fontMin)
                                .foregroundStyle(setting.isConfirmed ? theme.accent : theme.textSecondary)
                            Text(setting.title)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var threadSection: some View {
        Group {
            sectionHeader("线索", topPadding: 14, trailing: {
                Button {
                    session.openThreads()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("打开线索账本")
            })

            if session.threads.isEmpty {
                Text("还没有线索")
                    .font(theme.fontMin)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            } else {
                ForEach(session.threads) { thread in
                    Button {
                        session.openThreads(focus: thread.id)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(threadColor(thread.kind))
                                .frame(width: 6, height: 6)
                            Text(thread.name)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            if thread.isUnpaid {
                                Text("未收")
                                    .font(.system(size: 9))
                                    .foregroundStyle(theme.warning)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

    private var auditSection: some View {
        Group {
            sectionHeader("体检", topPadding: 14, trailing: {
                Button {
                    session.showAudit()
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .help("打开体检")
            })

            Button {
                session.showAudit()
            } label: {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: session.auditErrorCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal")
                        .foregroundStyle(session.auditErrorCount > 0 ? Color.red : theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        // 错误数当标题，警告与提示各占一行：窄侧栏里英文不会把词折开。
                        Text("错误 \(session.auditErrorCount)")
                            .foregroundStyle(session.auditErrorCount > 0 ? Color.red : theme.textSecondary)
                        Text("警告 \(session.auditWarningCount)")
                        Text("提示 \(session.auditInfoCount)")
                    }
                    Spacer(minLength: 0)
                }
                .font(theme.fontMin)
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func settingIconName(_ setting: Setting) -> String {
        if setting.isLocked { return "lock.fill" }
        return setting.isConfirmed ? "checkmark.seal" : "questionmark.circle"
    }

    private func sectionHeader(
        _ title: String,
        topPadding: CGFloat = 0,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 6) {
            Text(LocalizedStringKey(title))
                .font(theme.fontMinBold)
                .foregroundStyle(theme.textSecondary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
        .padding(.top, topPadding)
    }
}
