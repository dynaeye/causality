import CausalityCore
import SwiftUI

/// 故事板上的一张卡：文字直接可读，配图直接可见。
struct StoryboardCardView: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession
    let node: StoryNode

    private var isSelected: Bool { session.selectedNodeID == node.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let asset = coverAsset {
                CoverThumbnail(asset: asset, packageURL: session.packageURL, maxPixel: 520, cornerRadius: 0)
                    .frame(height: 132)
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 6) {
                titleRow
                titleText
                if !node.body.isEmpty {
                    Text(node.body)
                        .font(theme.fontBody)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !node.summary.isEmpty {
                    Text(node.summary)
                        .font(theme.fontBody)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(4)
                }
                if !cardThreads.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(cardThreads.prefix(4)) { thread in
                            Circle()
                                .fill(threadColor(thread.kind))
                                .frame(width: 6, height: 6)
                                .help(thread.name)
                        }
                        if cardThreads.count > 4 {
                            Text("+\(cardThreads.count - 4)")
                                .font(.system(size: 9))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                }
                if !chips.isEmpty {
                    FlowRow(spacing: 4) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(theme.fontMin)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(theme.border.opacity(0.45), in: Capsule())
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }
            }
            .padding(9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 2 : 1)
        }
        .overlay(alignment: .leading) {
            // 主线上的卡：左侧一道 accent 竖条，和故事图里的粗箭头对应。
            if session.mainline.contains(node: node.id) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 9,
                    bottomLeadingRadius: 9,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(theme.accent)
                .frame(width: 3)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture { selectCard() }
        .contextMenu { menu }
    }



    private func selectCard() {
        session.selectedNodeID = node.id
        session.insertion = nil
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if node.status == .idea {
                Text("念头")
                    .font(theme.fontMin)
                    .padding(.horizontal, 4)
                    .background(theme.warning.opacity(0.18), in: Capsule())
                    .foregroundStyle(theme.warning)
            } else if node.kind != .event {
                KindBadge(kind: node.kind)
            }
            if node.isEntry {
                Text("入口")
                    .font(theme.fontMin)
                    .padding(.horizontal, 4)
                    .background(theme.border.opacity(0.4), in: Capsule())
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
            if edgeCount > 0 {
                Label("\(edgeCount)", systemImage: "arrow.triangle.branch")
                    .font(theme.fontMin)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.bottom, 1)
    }

    private var titleText: some View {
        Text(verbatim: node.title.isEmpty ? InterfaceLanguage.label("未命名") : node.title)
            .font(theme.fontCardTitle)
            .foregroundStyle(theme.textPrimary)
            .lineLimit(3)
            .help(node.title.isEmpty ? InterfaceLanguage.label("未命名") : node.title)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var cardBackground: Color {
        if node.status == .idea {
            return theme.warning.opacity(theme.isDark ? 0.08 : 0.07)
        }
        return theme.surfaceRaised
    }

    private var coverAsset: Asset? {
        guard let assetID = node.coverAssetID else { return nil }
        return session.project?.asset(assetID)
    }

    private var cardThreads: [StoryThread] {
        session.threads(at: node.id)
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

    private var edgeCount: Int {
        (session.project?.edges ?? []).count { $0.from == node.id }
    }

    private var chips: [String] {
        guard let project = session.project else { return [] }
        let index = session.projectIndex ?? project.makeIndex()
        var values: [String] = []
        values += node.characterIDs.compactMap { index.characterByID[$0]?.name }
        values += node.placeIDs.compactMap { index.placeByID[$0]?.name }
        if let chapterID = node.chapterID, let chapter = project.chapter(chapterID), node.status == .idea {
            values.append(chapter.title)
        }
        return values
    }

    @ViewBuilder
    private var menu: some View {
        if node.status == .idea {
            Button("写成正式场景") {
                session.convertCard(node.id, to: .draft)
            }
        } else {
            // 选中之后进写作模式；enterWriting 会落在这一场，不用再找一遍。
            Button("写正文") {
                session.selectedNodeID = node.id
                session.enterWriting()
            }
            Button("退回成念头") {
                session.convertCard(node.id, to: .idea)
            }
        }
        Divider()
        if let chapterID = node.chapterID,
           let chapter = session.project?.chapter(chapterID),
           let index = chapter.order.firstIndex(of: node.id) {
            Button("上移一位") {
                session.moveCard(node.id, to: chapterID, at: max(0, index - 1))
            }
            .disabled(index == 0)
            Button("下移一位") {
                session.moveCard(node.id, to: chapterID, at: min(chapter.order.count, index + 2))
            }
            .disabled(index == chapter.order.count - 1)
        }
        Divider()
        ReachableEndingsMenu(session: session, nodeID: node.id)
        Divider()
        // 并列组：这张卡分出多条支线、又在同一章里汇合时，自动并排成一组。
        // 覆盖项只对「分叉点」有意义，所以非分叉且没覆盖过的卡不显示。
        let hasOverride = session.project?.cardGroupOverrides[node.id.rawValue.uuidString] != nil
        if edgeCount >= 2 || hasOverride {
            if hasOverride {
                Button("恢复自动并列组") {
                    session.setCardGroupOverride(node.id, nil)
                }
                .help("恢复成按分叉自动并排")
            } else {
                Button("这处分叉不并组") {
                    session.setCardGroupOverride(node.id, "ownGroup")
                }
                .help("并列组：一张卡分出多条支线、在同一章里又汇合。关掉之后这些支线各走各的列。")
            }
        }
        Divider()
        Button(node.isEntry ? LocalizedStringKey("取消故事入口") : LocalizedStringKey("设为故事入口")) {
            guard let project = session.project else { return }
            session.apply(
                ProjectMutations.setEntry(node.id, isEntry: !node.isEntry, in: project),
                name: "设置入口"
            )
        }
        Button("选择配图…") {
            session.pickImage(for: node.id)
        }
        Divider()
        Button("删除这张卡", role: .destructive) {
            guard let project = session.project else { return }
            session.apply(ProjectMutations.deleteNode(node.id, in: project), name: "删除卡片")
            if session.selectedNodeID == node.id {
                session.selectedNodeID = nil
            }
        }
    }
}
