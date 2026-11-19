import CausalityCore
import SwiftUI

/// 逐项对照。相互依赖的改动成组显示，整份一次撤销。
struct ProposalReviewSheet: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession
    @Environment(\.dismiss) private var dismiss

    private var proposal: ValidatedProposal? { session.pendingProposal }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let proposal {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        statusBanner(proposal)
                        if !proposal.proposal.payload.summary.isEmpty {
                            Text(proposal.proposal.payload.summary)
                                .font(theme.fontBody)
                        }
                        ForEach(proposal.groups) { group in
                            groupView(group, in: proposal)
                        }
                        if !proposal.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("说明与讨论建议")
                                    .font(theme.fontMin.weight(.medium))
                                    .foregroundStyle(.secondary)
                                ForEach(Array(proposal.notes.enumerated()), id: \.offset) { _, note in
                                    Text("· \(note)")
                                        .font(theme.fontMin)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("没有待审提案", systemImage: "sparkles")
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 560)
    }

    private var header: some View {
        HStack {
            Image(systemName: "checklist")
            Text("AI 提案")
                .font(theme.fontCardTitle)
            if let proposal {
                let tally = String(format: InterfaceLanguage.label("可采纳 %lld 项"), proposal.acceptedItems.count)
                    + String(format: InterfaceLanguage.label(" · 拒绝 %lld"), proposal.rejectedItems.count)
                    + String(format: InterfaceLanguage.label(" · 建议 %lld"), proposal.suggestionItems.count)
                Text(tally)
                    .font(theme.fontMin)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func statusBanner(_ proposal: ValidatedProposal) -> some View {
        Group {
            switch proposal.status {
            case .ready:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("版本一致，可以逐组采纳。")
                }
                .font(theme.fontMin)
            case let .stale(base, current):
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.orange)
                    Text(verbatim: String(
                        format: InterfaceLanguage.label("提案基于版本 %@，项目已经到 %@。请重新生成，避免覆盖新写的部分。"),
                        String(base),
                        String(current)
                    ))
                }
                .font(theme.fontMin)
            case let .conflicted(titles):
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("这些场景在等待期间被改过：\(titles.joined(separator: "、"))。可以重新生成，或手动合并。")
                }
                .font(theme.fontMin)
            }
        }
    }

    private func groupView(_ group: ProposalGroup, in proposal: ValidatedProposal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group.title)
                    .font(theme.fontMin.weight(.medium))
                if group.itemIDs.count > 1 {
                    Text("成组采纳")
                        .font(theme.fontMin)
                        .padding(.horizontal, 4)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if group.adoptableItemIDs.isEmpty {
                    Text("\(group.itemIDs.count) 项建议")
                        .font(theme.fontMin)
                        .foregroundStyle(.secondary)
                } else if group.adoptableItemIDs.allSatisfy(session.adoptedProposalItems.contains) {
                    Label("已采纳", systemImage: "checkmark.circle.fill")
                        .font(theme.fontMin)
                        .foregroundStyle(.green)
                } else {
                    Text("\(group.adoptableItemIDs.count)/\(group.itemIDs.count) 可采纳")
                        .font(theme.fontMin)
                        .foregroundStyle(.secondary)
                    Button("采纳本组") {
                        session.adoptPendingProposal(itemIDs: group.adoptableItemIDs)
                    }
                    .font(theme.fontMin)
                    .disabled(proposal.status != .ready)
                    .help("这一组一起落地，与其他组互不影响")
                }
            }
            ForEach(group.itemIDs, id: \.self) { itemID in
                if let item = proposal.items.first(where: { $0.id == itemID }) {
                    itemView(item)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
    }

    private func itemView(_ item: ProposalItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: outcomeSymbol(item.outcome))
                .foregroundStyle(outcomeColor(item.outcome))
                .font(theme.fontMin)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(item.action.displayName))
                        .font(theme.fontMin)
                        .foregroundStyle(.secondary)
                    Text(item.title)
                        .font(theme.fontBody)
                }
                ForEach(item.detail) { diff in
                    diffView(diff)
                }
                if let explanation = item.outcome.explanation {
                    Text(explanation)
                        .font(theme.fontMin)
                        .foregroundStyle(outcomeColor(item.outcome))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func diffView(_ diff: FieldDiff) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(diff.field)
                .font(theme.fontMin)
                .foregroundStyle(.secondary)
            if !diff.before.isEmpty {
                Text(diff.before)
                    .font(theme.fontMin)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(diff.after)
                .font(theme.fontMin)
                .lineLimit(3)
        }
        .padding(.leading, 2)
    }

    private func outcomeSymbol(_ outcome: ProposalItem.Outcome) -> String {
        switch outcome {
        case .accept: "checkmark.circle.fill"
        case .reject: "xmark.octagon"
        case .suggestion: "text.bubble"
        }
    }

    private func outcomeColor(_ outcome: ProposalItem.Outcome) -> Color {
        switch outcome {
        case .accept: .green
        case .reject: .red
        case .suggestion: .orange
        }
    }

    private var footer: some View {
        HStack {
            if let error = session.aiLastError {
                Text(error)
                    .font(theme.fontMin)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button("放弃") {
                session.discardPendingProposal()
                dismiss()
            }
            Button(adoptTitle) {
                session.adoptPendingProposal()
            }
            .buttonStyle(.borderedProminent)
            .disabled(proposal?.isAdoptable != true)
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var adoptTitle: String {
        guard let proposal else { return InterfaceLanguage.label("采纳") }
        return String(
            format: InterfaceLanguage.label("采纳 %lld 项（可撤销）"),
            proposal.acceptedItems.count
        )
    }
}
