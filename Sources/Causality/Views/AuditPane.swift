import CausalityCore
import SwiftUI

/// 体检面板：按严重度筛问题，点条跳到对应卡片，可带理由忽略。
struct AuditPane: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession

    @State private var filter: AuditFilter = .all
    @State private var waiverTarget: AuditFinding?
    @State private var waiverReason = ""
    @State private var showingWaived = false

    private enum AuditFilter: String, CaseIterable, Identifiable {
        case all
        case error
        case warning
        case info

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .all: "全部"
            case .error: "错误"
            case .warning: "警告"
            case .info: "提示"
            }
        }

        func matches(_ finding: AuditFinding) -> Bool {
            switch self {
            case .all: true
            case .error: finding.severity == .error
            case .warning: finding.severity == .warning
            case .info: finding.severity == .info
            }
        }
    }

    private var filtered: [AuditFinding] {
        session.auditFindings.filter { filter.matches($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(theme.border).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        ForEach(filtered) { finding in
                            row(finding)
                        }
                    }
                    warningsSection
                    if showingWaived {
                        waivedSection
                    }
                }
                .padding(20)
                .frame(maxWidth: 900, alignment: .center)
                .frame(maxWidth: .infinity)
            }
        }
        .background(theme.background)
        .alert(
            "忽略这条体检？",
            isPresented: Binding(
                get: { waiverTarget != nil },
                set: { if !$0 { waiverTarget = nil } }
            ),
            presenting: waiverTarget
        ) { finding in
            TextField("理由（可空）", text: $waiverReason)
            Button("忽略") {
                session.waive(finding, reason: waiverReason)
                waiverTarget = nil
            }
            Button("取消", role: .cancel) { waiverTarget = nil }
        } message: { finding in
            Text("「\(finding.rule) \(finding.title)」将不再出现在体检里；理由会随工程包保存。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("体检")
                .font(theme.fontTitle)
            countPill(session.auditErrorCount, key: "错误 %lld", color: .red)
            countPill(session.auditWarningCount, key: "警告 %lld", color: theme.warning)
            countPill(session.auditInfoCount, key: "提示 %lld", color: theme.textTertiary)

            Spacer()

            Picker("筛选", selection: $filter) {
                ForEach(AuditFilter.allCases) { value in
                    Text(LocalizedStringKey(value.displayName)).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(minWidth: 260)

            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    showingWaived.toggle()
                }
            } label: {
                Text("已忽略 \(session.auditWaivedFindings.count) 条")
                    .font(theme.fontMin)
            }
            .buttonStyle(.link)

            Button {
                session.revalidateWarnings()
                session.refreshAudit()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("重新体检")

            Button {
                session.closeAudit()
            } label: {
                Label("关闭", systemImage: "xmark")
            }
            .controlSize(.small)
            .help("回到原来的视图")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(theme.surface)
    }

    private func countPill(_ count: Int, key: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(verbatim: String(format: InterfaceLanguage.label(key), count))
                .font(theme.fontMin)
                .foregroundStyle(count > 0 ? color : theme.textTertiary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.accent)
            Text(filter == .all ? LocalizedStringKey("体检通过") : LocalizedStringKey("这一类里没有问题"))
                .font(theme.fontCardTitle)
                .foregroundStyle(theme.textPrimary)
            Text("故事结构、分支与人物出场都没有报出问题。")
                .font(theme.fontMin)
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func row(_ finding: AuditFinding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(severityColor(finding.severity))
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(finding.rule)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                    Text(finding.title)
                        .font(theme.fontBody)
                        .foregroundStyle(theme.textPrimary)
                    Text(LocalizedStringKey(finding.severity.displayName))
                        .font(.system(size: 10))
                        .foregroundStyle(severityColor(finding.severity))
                }
                Text(finding.message)
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if finding.nodeID != nil {
                Button("跳到") { jump(finding) }
                    .controlSize(.small)
            }
            Button("忽略") {
                waiverReason = ""
                waiverTarget = finding
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var warningsSection: some View {
        if !session.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(verbatim: String(format: InterfaceLanguage.label("工程提示 %lld 条"), session.warnings.count))
                        .font(theme.fontMinBold)
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    Button("清空") { session.clearWarnings() }
                        .buttonStyle(.link)
                        .font(theme.fontMin)
                }
                .padding(.top, 10)

                ForEach(Array(session.warnings.enumerated()), id: \.offset) { index, warning in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(theme.textTertiary)
                            .padding(.top, 1)
                        Text(warning)
                            .font(theme.fontMin)
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("知道了") { session.dismissWarning(at: index) }
                            .controlSize(.small)
                    }
                    .padding(8)
                    .background(theme.border.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    @ViewBuilder
    private var waivedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("已忽略")
                .font(theme.fontMinBold)
                .foregroundStyle(theme.textSecondary)
                .padding(.top, 10)
            if session.auditWaivedFindings.isEmpty {
                Text("还没有忽略任何问题。")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
            }
            ForEach(session.auditWaivedFindings) { finding in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(finding.rule) \(finding.title)")
                            .font(theme.fontMin)
                            .foregroundStyle(theme.textSecondary)
                        if let reason = session.waiver(for: finding)?.reason, !reason.isEmpty {
                            Text(reason)
                                .font(theme.fontMin)
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    Spacer()
                    Button("恢复") {
                        if let waiver = session.waiver(for: finding) {
                            session.restoreWaiver(waiver)
                        }
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(theme.border.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func jump(_ finding: AuditFinding) {
        guard let nodeID = finding.nodeID,
              let node = session.project?.node(nodeID) else { return }
        session.selectedNodeID = nodeID
        session.focusedChapterID = node.chapterID
        session.viewMode = node.status == .idea ? .storyboard : .outline
        session.closeAudit()
    }

    private func severityColor(_ severity: AuditFinding.Severity) -> Color {
        switch severity {
        case .error: .red
        case .warning: theme.warning
        case .info: theme.textTertiary
        }
    }
}
