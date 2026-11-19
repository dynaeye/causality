import CausalityCore
import SwiftUI

/// 试玩：单路径步行，面包屑回退，选项就是连线上的文字。
struct PlaythroughPane: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession

    private var play: Playthrough? { session.playthrough }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(theme.border).frame(height: 1)
            if let play, let current = play.current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        breadcrumbs(play)
                        scene(current, play: play)
                        options(current, play: play)
                    }
                    .padding(22)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                emptyState
            }
        }
        .background(theme.background)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("试玩")
                .font(theme.fontTitle)
            if let play {
                Text("\(play.stepCount) 步 · 累计 \(WordCountText.text(play.cumulativeWords))")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer()
            Button {
                session.backPlaythrough()
            } label: {
                Label("回退", systemImage: "arrow.uturn.left")
            }
            .controlSize(.small)
            .disabled((play?.stepCount ?? 0) <= 1)

            Button {
                session.restartPlaythrough()
            } label: {
                Label("从头开始", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)

            Button("导出试读稿…") { session.exportPlaythrough() }
                .controlSize(.small)
                .disabled(play == nil)

            Button {
                session.closePlaythrough()
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
            Image(systemName: "play.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text("没有可试玩的正式场景")
                .font(theme.fontCardTitle)
                .foregroundStyle(theme.textPrimary)
            Text("先在故事板里写一张卡，标成入口。")
                .font(theme.fontMin)
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func breadcrumbs(_ play: Playthrough) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(play.steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Button {
                        session.jumpPlaythrough(to: index)
                    } label: {
                        Text(step.node.title)
                            .font(theme.fontMin)
                            .foregroundStyle(index == play.steps.count - 1 ? theme.textPrimary : theme.textTertiary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func scene(_ step: PlaythroughStep, play: Playthrough) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(session.chapterTitle(step.node.chapterID))
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
                Text(step.node.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("第 \(step.stepNumber) 步 · 累计 \(WordCountText.text(step.cumulativeWords))")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
            }
            if let incoming = step.incomingLabel, !incoming.isEmpty {
                Text("← \(incoming)")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textSecondary)
            }
            Text(verbatim: step.node.body.isEmpty ? InterfaceLanguage.label("（这一场还没有正文）") : step.node.body)
                .font(.system(size: 17))
                .lineSpacing(7)
                .foregroundStyle(step.node.body.isEmpty ? theme.textTertiary : theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(theme.surfaceRaised.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func options(_ step: PlaythroughStep, play: Playthrough) -> some View {
        if play.finished {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(theme.accent)
                Text("到达结局「\(step.node.title)」")
                    .font(theme.fontBody)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button("再走一遍") { session.restartPlaythrough() }
                    .controlSize(.small)
            }
            .padding(12)
            .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
        } else if play.deadEnd {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.warning)
                Text("这条路到这里断了：没有去向，也不是结局。")
                    .font(theme.fontBody)
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Button("打开体检") {
                    session.closePlaythrough()
                    session.showAudit()
                }
                .controlSize(.small)
            }
            .padding(12)
            .background(theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("去向")
                    .font(theme.fontMinBold)
                    .foregroundStyle(theme.textSecondary)
                ForEach(Array(step.options.enumerated()), id: \.element.id) { index, option in
                    Button {
                        session.choosePlaythrough(option.edgeID)
                    } label: {
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 18, height: 18)
                                .background(theme.border.opacity(0.5), in: Circle())
                                .foregroundStyle(theme.textTertiary)
                            Text(option.label)
                                .font(theme.fontBody)
                                .foregroundStyle(theme.textPrimary)
                            if !option.condition.isEmpty {
                                Text("（条件：\(option.condition)）")
                                    .font(theme.fontMin)
                                    .foregroundStyle(theme.textTertiary)
                            }
                            Spacer()
                            Text("\(option.targetChapterTitle) · \(option.targetTitle)")
                                .font(theme.fontMin)
                                .foregroundStyle(theme.textTertiary)
                                .lineLimit(1)
                        }
                        .padding(10)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(theme.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
