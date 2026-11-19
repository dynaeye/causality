import CausalityCore
import SwiftUI

/// 讨论记录与流式输出。
struct AIPanelMessages: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession
    @State private var hoveredMessageID: Message.ID?


    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if session.conversationMessages.isEmpty, !session.aiState.isBusy {
                        Text("选中一个场景，问一个问题；或者直接让它整理成大纲。")
                            .font(theme.fontMin)
                            .foregroundStyle(theme.textSecondary)
                            .padding(.top, 12)
                    }
                    ForEach(session.conversationMessages) { message in
                        messageRow(message)
                    }
                    if case let .streaming(text) = session.aiState {
                        bubble(text.isEmpty ? "…" : text, role: .assistant)
                    }
                    if case .waiting = session.aiState {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("已发出，等待首个字…")
                                .font(theme.fontMin)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                    if case let .failed(reason) = session.aiState {
                        Text(reason)
                            .font(theme.fontMin)
                            .foregroundStyle(.red)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: session.conversationMessages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: session.aiState) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func messageRow(_ message: Message) -> some View {
        VStack(alignment: message.role == .author ? .trailing : .leading, spacing: 3) {
            bubble(message.text, role: message.role)
            if message.role != .system {
                // 常驻一行、只换透明度：hover 区不会因为多出一行而丢，按钮才点得到。
                actions(for: message)
                    .opacity(hoveredMessageID == message.id ? 1 : 0)
                    .allowsHitTesting(hoveredMessageID == message.id)
            }
        }
        .onHover { inside in
            if inside {
                hoveredMessageID = message.id
            } else if hoveredMessageID == message.id {
                hoveredMessageID = nil
            }
        }
    }

    /// 一句话落地：收为灵感 / 记为设定 / 插到锚点后。三个动作各走一笔 EditOperation。
    private func actions(for message: Message) -> some View {
        HStack(spacing: 6) {
            captureButton("收为灵感", systemImage: "lightbulb") {
                session.captureMessageAsIdea(message.text)
            }
            captureButton("记为设定", systemImage: "checkmark.seal") {
                session.captureMessageAsSetting(message.text)
            }
            captureButton(
                "插到此处",
                systemImage: "plus.rectangle.on.rectangle",
                disabled: session.insertion == nil,
                help: session.insertion == nil ? "先在故事板上点一处缝隙" : "插到当前锚点后"
            ) {
                session.insertMessageCard(message.text)
            }
        }
    }

    private func captureButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        disabled: Bool = false,
        help: LocalizedStringKey = "",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(theme.border.opacity(0.35), in: Capsule())
        .foregroundStyle(disabled ? theme.textTertiary.opacity(0.45) : theme.textSecondary)
        .disabled(disabled)
        .help(help)
    }

    private func bubble(_ text: String, role: MessageRole) -> some View {
        HStack {
            if role == .author { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text(roleLabel(role))
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
                Text(text)
                    .font(theme.fontBody)
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .background(bubbleColor(role), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if role != .author { Spacer(minLength: 40) }
        }
    }

    private func roleLabel(_ role: MessageRole) -> String {
        switch role {
        case .author: InterfaceLanguage.label("我")
        case .assistant: "AI"
        case .system: InterfaceLanguage.label("系统")
        }
    }

    private func bubbleColor(_ role: MessageRole) -> Color {
        switch role {
        case .author: theme.accentSoft
        case .assistant: theme.surfaceRaised
        case .system: theme.warning.opacity(0.12)
        }
    }
}
