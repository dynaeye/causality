import CausalityCore
import SwiftUI

/// 分支梗概：每个结局一组，讲清怎么走到这里；润色结果只留在面板里。
struct SynopsisPane: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession
    @State private var expanded: Set<NodeID> = []

    private var groups: [BranchSynopsis] { session.synopsisGroups }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(theme.border).frame(height: 1)
            if groups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        sharedChapterBanner
                        ForEach(groups, id: \.endingID) { group in
                            groupView(group)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 940, alignment: .center)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(theme.background)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("分支梗概")
                .font(theme.fontTitle)
            Text(String(format: InterfaceLanguage.label("%lld 个结局"), groups.count))
                .font(theme.fontMin)
                .foregroundStyle(theme.textTertiary)

            Spacer()

            Picker("模式", selection: Binding(
                get: { session.synopsisMode },
                set: { session.setSynopsisMode($0) }
            )) {
                Text("分段").tag(BranchSynopsis.Mode.segments)
                Text("逐条").tag(BranchSynopsis.Mode.perPath)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)

            Button("重新生成") { session.refreshSynopsis() }
                .controlSize(.small)

            Button("导出 Markdown…") { session.exportSynopsisMarkdown() }
                .controlSize(.small)
                .disabled(groups.isEmpty)

            Button {
                session.closeSynopsis()
            } label: {
                Label("关闭", systemImage: "xmark")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(theme.surface)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.append")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text("还没有结局")
                .font(theme.fontCardTitle)
                .foregroundStyle(theme.textPrimary)
            Text("标一张卡为结局之后，这里会按结局列出分支梗概。")
                .font(theme.fontMin)
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var sharedChapterBanner: some View {
        let shared = session.project.map { BranchSynopsis.sharedChapters(in: $0) } ?? []
        if !shared.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.warning)
                Text(String(format: InterfaceLanguage.label("「%@」覆盖全部结局，读者每次都会经过。"), shared.map(\.title).joined(separator: InterfaceLanguage.listSeparator)))
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textSecondary)
                Spacer()
            }
            .padding(10)
            .background(theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func groupView(_ group: BranchSynopsis) -> some View {
        let isExpanded = expanded.contains(group.endingID)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(String(format: InterfaceLanguage.label("结局 · %@"), group.endingTitle))
                    .font(theme.fontCardTitle)
                    .foregroundStyle(theme.textPrimary)
                badge(LocalizedStringKey(String(format: InterfaceLanguage.label("%lld 张"), group.cardCount)))
                badge(LocalizedStringKey(WordCountText.text(group.stats.wordCount)), warning: group.stats.thin)
                if group.stats.thin {
                    Text("结局薄")
                        .font(.system(size: 10))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(theme.warning.opacity(0.16), in: Capsule())
                        .foregroundStyle(theme.warning)
                        .help(String(format: InterfaceLanguage.label("独占卡只有 %lld 张：这个结局和别的结局走得太近。"), group.stats.exclusiveCount))
                }
                if group.truncated {
                    Text("分支超过 24 条，按分叉分块")
                        .font(theme.fontMin)
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
                Button(isExpanded ? LocalizedStringKey("收起") : LocalizedStringKey("更多")) {
                    if isExpanded {
                        expanded.remove(group.endingID)
                    } else {
                        expanded.insert(group.endingID)
                    }
                }
                .controlSize(.small)
            }

            if isExpanded {
                HStack(spacing: 14) {
                    stat("选择点", "\(group.stats.choiceCount)")
                    stat("独占卡", "\(group.stats.exclusiveCount)")
                    if let shortest = group.stats.shortestSteps {
                        stat("最短", LocalizedStringKey(String(format: InterfaceLanguage.label("%lld 步"), shortest)))
                    }
                    if let longest = group.stats.longestSteps {
                        stat("最长", LocalizedStringKey(String(format: InterfaceLanguage.label("%lld 步"), longest)))
                    }
                }
                .padding(.bottom, 2)
            }

            if group.blocks.isEmpty {
                Text("这条结局还没有可枚举的路径。")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
            }

            ForEach(group.blocks) { block in
                blockView(block)
            }
        }
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.border, lineWidth: 1)
        }
    }

    private func blockView(_ block: BranchBlock) -> some View {
        let key = session.synopsisPolishKey(block)
        let polished = session.synopsisPolish[key]
        let error = session.synopsisPolishErrors[key]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(block.label)
                    .font(theme.fontMinBold)
                    .foregroundStyle(theme.textSecondary)
                Text(String(format: InterfaceLanguage.label("%lld 张 · %lld 字"), block.cardCount, blockWordCount(block)))
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                if session.synopsisPolishing.contains(key) {
                    ProgressView()
                        .controlSize(.mini)
                }
                Button(polished == nil ? LocalizedStringKey("润色") : LocalizedStringKey("重新润色")) {
                    session.polishSynopsis(block)
                }
                .controlSize(.small)
                .disabled(session.synopsisPolishing.contains(key))
            }

            Text(block.text)
                .font(theme.fontBody)
                .lineSpacing(3)
                .foregroundStyle(theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let polished {
                VStack(alignment: .leading, spacing: 3) {
                    Text("润色 · 只在这个面板里")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.accent)
                    Text(polished)
                        .font(theme.fontBody)
                        .lineSpacing(3)
                        .foregroundStyle(theme.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 7))
            }

            if let error {
                Text(error)
                    .font(theme.fontMin)
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(theme.surfaceRaised.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func badge(_ text: LocalizedStringKey, warning: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 10))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background((warning ? theme.warning : theme.border).opacity(0.18), in: Capsule())
            .foregroundStyle(warning ? theme.warning : theme.textSecondary)
    }

    private func stat(_ label: LocalizedStringKey, _ value: LocalizedStringKey) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(theme.textTertiary)
            Text(value)
                .foregroundStyle(theme.textSecondary)
        }
        .font(theme.fontMin)
    }

    private func blockWordCount(_ block: BranchBlock) -> Int {
        block.nodeIDs.reduce(0) { total, id in
            guard let node = session.project?.node(id) else { return total }
            return total + WordCount.count(of: node)
        }
    }
}
