import CausalityCore
import SwiftUI

/// 右栏的对话面板：整列高度都留给消息，输入区固定在底部。
struct AIPanel: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession
    @State private var showingClearDiscussion = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.border)
            referenceSection
                .padding(.bottom, 8)
            Divider().overlay(theme.border)
            AIPanelMessages(session: session)
                .frame(maxHeight: .infinity)
            Divider().overlay(theme.border)
            inputSection
        }
        .background(theme.surface)
        .alert("清空讨论记录？", isPresented: $showingClearDiscussion) {
            Button("清空", role: .destructive) {
                session.clearAIDiscussion()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会清空当前讨论的全部消息，讨论本身和引用材料保留；可以用 ⌘Z 撤销。")
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(theme.textSecondary)
                Text("AI 辅助")
                    .font(theme.fontBodyMedium)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if session.aiState.isBusy {
                    ProgressView().controlSize(.small)
                }
            }

            HStack(spacing: 6) {
                if let insertionLabel {
                    Text(String(format: InterfaceLanguage.label("插入位置：%@"), insertionLabel))
                        .font(theme.fontMin)
                        .foregroundStyle(theme.warning)
                        .lineLimit(2)
                } else {
                    Text(selectionLabel)
                        .font(theme.fontMin)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Picker("范围", selection: $session.aiContextScope) {
                    ForEach(AIContextScope.allCases, id: \.self) { scope in
                        Text(LocalizedStringKey(scope.displayName)).tag(scope)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var insertionLabel: String? {
        guard let insertion = session.insertion,
              let project = session.project,
              let chapter = project.chapter(insertion.chapterID) else { return nil }
        let anchor = insertion.anchorNodeID.flatMap { project.node($0)?.title }
        return anchor.map {
            String(format: InterfaceLanguage.label("%@ · 在「%@」之后"), chapter.title, $0)
        } ?? String(format: InterfaceLanguage.label("%@ · 开头"), chapter.title)
    }

    private var selectionLabel: String {
        guard let project = session.project, let id = session.selectedNodeID,
              let node = project.node(id) else {
            return session.aiContextScope == .project
                ? InterfaceLanguage.label("全书")
                : InterfaceLanguage.label("未选中场景")
        }
        return String(format: InterfaceLanguage.label("选中：%@"), node.title)
    }

    // MARK: 引用材料

    private var referenceSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("本轮引用")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textSecondary)
                if let context = session.liveContext {
                    Text(String(format: InterfaceLanguage.label("%lld 项"), context.references.count))
                        .font(theme.fontMin)
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
                if !session.aiExcludedReferences.isEmpty {
                    Button("全部恢复") { session.aiExcludedReferences.removeAll() }
                        .buttonStyle(.link)
                        .font(theme.fontMin)
                }
            }
            ScrollView(.vertical) {
                FlowRow(spacing: 4) {
                    ForEach(allReferences, id: \.id) { reference in
                        referenceChip(reference)
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(maxHeight: 74)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func referenceChip(_ reference: AIContext.Reference) -> some View {
        let excluded = session.aiExcludedReferences.contains(reference.id)
        return Button {
            session.toggleReference(reference)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: symbol(for: reference.kind))
                    .font(.system(size: 10))
                Text(reference.title)
                    .lineLimit(1)
                Image(systemName: excluded ? "plus.circle" : "xmark.circle.fill")
                    .font(.system(size: 10))
            }
            .font(theme.fontMin)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                excluded ? theme.border.opacity(0.25) : theme.accentSoft,
                in: Capsule()
            )
            .foregroundStyle(excluded ? theme.textTertiary : theme.textPrimary)
        }
        .buttonStyle(.plain)
        .help(LocalizedStringKey(excluded ? "重新加入本轮材料" : "从本轮材料里移除"))
    }

    private var allReferences: [AIContext.Reference] {
        guard let project = session.project else { return [] }
        return PromptBuilder.makeContext(
            kind: .editSelection,
            contextScope: session.aiContextScope,
            selection: session.selectedNodeID,
            project: project
        ).references
    }

    private func symbol(for kind: AIContext.Reference.Kind) -> String {
        switch kind {
        case .node: "square.text.square"
        case .edge: "arrow.triangle.branch"
        case .setting: "checkmark.seal"
        case .character: "person"
        case .place: "mappin.and.ellipse"
        case .asset: "photo"
        case .chapter: "book.closed"
        }
    }

    // MARK: 输入

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $session.aiInstruction)
                .font(theme.fontBody)
                .scrollContentBackground(.hidden)
                .frame(height: 96)
                .padding(6)
                .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.border, lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if session.aiInstruction.isEmpty {
                        Text("输入内容，并选择修改选中内容、整理大纲或只讨论")
                            .font(theme.fontMin)
                            .foregroundStyle(theme.textTertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }

            if let error = session.aiLastError, !session.aiState.isBusy {
                HStack(spacing: 6) {
                    Text(error)
                        .font(theme.fontMin)
                        .foregroundStyle(theme.warning)
                        .lineLimit(2)
                    Spacer()
                    Button("重试") { runPrimary() }
                        .font(theme.fontMin)
                }
            }
            actionRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// 主按钮：产出提案。按当前上下文决定默认动作，下拉里可以换范围。
    private var proposalButton: some View {
        Menu {
            Button("修改选中内容") { session.requestEditSelection() }
                .disabled(session.selectedNodeID == nil)
            if session.insertion != nil {
                Button("在这里插一张卡") { session.requestInsertCard() }
            }
            Button("整理成大纲") { session.requestOutline() }
        } label: {
            Label(primaryTitle, systemImage: primaryIcon)
                .frame(maxWidth: .infinity)
        } primaryAction: {
            runPrimary()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(session.aiState.isBusy)
        .help(String(format: InterfaceLanguage.label("点按执行「%@」，也可以从下拉里换一种提案范围"), primaryTitle))
    }

    private var primaryTitle: String {
        if session.insertion != nil { return InterfaceLanguage.label("在这里插一张卡") }
        if session.selectedNodeID != nil { return InterfaceLanguage.label("修改选中内容") }
        return InterfaceLanguage.label("整理成大纲")
    }

    private var primaryIcon: String {
        session.insertion != nil ? "plus.rectangle.on.rectangle" : "wand.and.stars"
    }

    private func runPrimary() {
        if session.insertion != nil {
            session.requestInsertCard()
        } else if session.selectedNodeID != nil {
            session.requestEditSelection()
        } else {
            session.requestOutline()
        }
    }

    /// 主操作、只讨论与取消放在同一排。
    private var actionRow: some View {
        HStack(spacing: 8) {
            proposalButton
                .layoutPriority(1)

            Button {
                session.sendDiscussion()
            } label: {
                Label("只讨论", systemImage: "bubble.left.and.bubble.right")
            }
            .controlSize(.regular)
            .disabled(session.aiState.isBusy)
            .help("只聊，不改动项目，也不产出提案")

            if session.aiState.isBusy {
                Button("取消", role: .cancel) { session.cancelAI() }
                    .controlSize(.regular)
            }

            if !session.conversationMessages.isEmpty {
                Button {
                    showingClearDiscussion = true
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .controlSize(.regular)
                .disabled(session.aiState.isBusy)
                .help("清空当前讨论的过去消息")
            }
        }
    }
}
