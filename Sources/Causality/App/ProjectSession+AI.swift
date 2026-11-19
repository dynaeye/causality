import Foundation
import CausalityCore
import SwiftUI

// MARK: - 凭据（转发到共享设置）

extension ProjectSession {
    var hasCredential: Bool { ai.hasCredential }

    func loadCredential() -> AICredential? { ai.loadCredential() }

    func saveCredential(_ key: String) { ai.saveCredential(key) }

    func clearCredential() { ai.clearCredential() }

    func refreshModels() { ai.refreshModels() }

    // 已在 ProjectSession 里定义(_ provider: AIProvider) { ai.selectProvider(provider) }

    // 已在 ProjectSession 里定义(_ model: String) { ai.selectModel(model) }

    // 已在 ProjectSession 里定义() { ai.refreshCredentialStatus() }

    /// 打开系统设置窗口。
    func openAISettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - 上下文与引用

extension ProjectSession {
    /// 当前选中项会带出去的材料。面板上的引用条读它。
    var liveContext: AIContext? {
        guard let project else { return nil }
        return PromptBuilder.makeContext(
            kind: .editSelection,
            contextScope: aiContextScope,
            selection: selectedNodeID,
            project: project,
            excluded: aiExcludedReferences
        )
    }

    func toggleReference(_ reference: AIContext.Reference) {
        if aiExcludedReferences.contains(reference.id) {
            aiExcludedReferences.remove(reference.id)
        } else {
            aiExcludedReferences.insert(reference.id)
        }
    }

    var conversationMessages: [Message] {
        guard let project, let discussionID = aiDiscussionID else { return [] }
        return project.discussions.first { $0.id == discussionID }?.messages ?? []
    }
}

// MARK: - 讨论与提案

extension ProjectSession {
    func sendDiscussion() {
        runAI(kind: .discussion)
    }

    func requestOutline() {
        runAI(kind: .outline)
    }

    func requestEditSelection() {
        runAI(kind: .editSelection)
    }

    func requestInsertCard() {
        runAI(kind: .insertCard)
    }

    func cancelAI() {
        aiTask?.cancel()
        aiTask = nil
        aiState = .idle
        aiLastError = nil
        if let discussionID = aiDiscussionID {
            appendMessage(InterfaceLanguage.label("（已取消这次请求）"), role: .system, to: discussionID)
        }
    }

    private func runAI(kind: AIRequestKind) {
        commitAllTextDrafts()
        guard let project else { return }
        let instruction = aiInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            reportBlockedAI(InterfaceLanguage.label("先写一句要 AI 做什么"))
            return
        }
        if kind == .insertCard, insertion == nil {
            reportBlockedAI(InterfaceLanguage.label("先在故事板上点一处缝隙"))
            return
        }
        let role = kind.usageRole
        guard let choice = ai.choice(for: role),
              let roleProvider = ai.provider(id: choice.providerID),
              !choice.model.isEmpty else {
            reportBlockedAI(String(format: InterfaceLanguage.label("先在 AI 设置里给「%@」选一个服务和模型"), InterfaceLanguage.label(role.displayName)))
            openAISettings()
            return
        }
        guard let credential = ai.loadCredential(for: roleProvider.id) else {
            if roleProvider.id == AIProvider.chatGPT.id, ai.chatGPTAuthState == .expired {
                reportBlockedAI(InterfaceLanguage.label("ChatGPT 登录已过期，请在 Agent 设置里重新网页登录"))
            } else {
                reportBlockedAI(String(format: InterfaceLanguage.label("还没有配置 %@ 的 API key"), roleProvider.localizedDisplayName))
            }
            openAISettings()
            return
        }

        let discussionID = ensureDiscussion()
        let history = recentTurns(in: discussionID)
        appendMessage(instruction, role: .author, to: discussionID)
        let context = PromptBuilder.makeContext(
            kind: kind,
            contextScope: aiContextScope,
            selection: selectedNodeID,
            project: project,
            insertion: insertion,
            excluded: aiExcludedReferences
        )
        aiLastContext = context
        aiState = .waiting
        aiLastError = nil

        let request = ProposalRequest(
            kind: kind,
            instruction: instruction,
            contextScope: aiContextScope,
            selection: selectedNodeID,
            provider: roleProvider,
            model: choice.model,
            credential: credential,
            excludedReferences: aiExcludedReferences,
            history: history,
            insertion: kind == .insertCard ? insertion : nil
        )

        aiTask?.cancel()
        aiTask = Task { [weak self] in
            guard let self else { return }
            if kind == .discussion {
                await self.streamDiscussion(request: request, project: project, discussionID: discussionID)
            } else {
                await self.collectProposal(request: request, project: project, discussionID: discussionID)
            }
        }
    }

    /// 最近十二轮、最多六千字。作者说「按刚才那个调子」时，模型得看得见「刚才」。
    private func recentTurns(in discussionID: DiscussionID, limit: Int = 12, characterBudget: Int = 6000) -> [AIChatTurn] {
        guard let project, let discussion = project.discussions.first(where: { $0.id == discussionID }) else {
            return []
        }
        var turns: [AIChatTurn] = []
        var remaining = characterBudget
        for message in discussion.messages.reversed() {
            guard turns.count < limit, remaining > 0 else { break }
            let role: AIChatTurn.Role
            switch message.role {
            case .author: role = .user
            case .assistant: role = .assistant
            case .system: continue
            }
            let text = String(message.text.prefix(remaining))
            remaining -= text.count
            turns.append(AIChatTurn(role: role, text: text))
        }
        return turns.reversed()
    }

    private func streamDiscussion(
        request: ProposalRequest,
        project: StoryProject,
        discussionID: DiscussionID
    ) async {
        let stream = await proposalService.streamDiscussion(
            request,
            project: project,
            localize: workLanguage.label
        )
        var text = ""
        var note: String?
        do {
            for try await event in stream {
                switch event {
                case let .textDelta(delta):
                    text += delta
                    aiState = .streaming(text)
                case let .completed(completion):
                    text = completion.text.isEmpty ? text : completion.text
                    note = completion.note
                }
            }
            aiState = .idle
            // 断流或撞到上限时也要把已收到的正文留下来，再补一句说明。
            appendMessage(text, role: .assistant, to: discussionID)
            if let note {
                appendMessage(String(format: InterfaceLanguage.label("（%@）"), note), role: .system, to: discussionID)
                aiLastError = note
            }
            aiInstruction = ""
        } catch {
            handleAIError(error, discussionID: discussionID, role: request.kind.usageRole)
        }
    }

    private func collectProposal(
        request: ProposalRequest,
        project: StoryProject,
        discussionID: DiscussionID
    ) async {
        do {
            let result = try await proposalService.run(
                request,
                project: project,
                localize: workLanguage.label
            )
            aiState = .idle
            if let validated = result.validated {
                pendingProposal = validated
                showingProposalSheet = true
                appendMessage(
                    String(
                        format: InterfaceLanguage.label("提案：%@（可采纳 %lld 项）"),
                        validated.proposal.payload.summary,
                        validated.acceptedItems.count
                    ),
                    role: .assistant,
                    to: discussionID
                )
                aiInstruction = ""
            } else {
                let reason = result.parseFailure ?? InterfaceLanguage.label("没有拿到可用的提案")
                aiState = .failed(reason)
                aiLastError = reason
                appendMessage(String(format: InterfaceLanguage.label("（提案无法解析：%@）"), reason), role: .system, to: discussionID)
            }
        } catch {
            handleAIError(error, discussionID: discussionID, role: request.kind.usageRole)
        }
    }

    /// 发不出去的情况也只留一条提示：写进对话记录。
    func reportBlockedAI(_ message: String) {
        aiLastError = message
        let discussionID = ensureDiscussion()
        appendMessage(String(format: InterfaceLanguage.label("（没能发出：%@）"), message), role: .system, to: discussionID)
    }

    /// 失败时保留作者输入，并把可操作的下一步说出来。
    private func handleAIError(_ error: Error, discussionID: DiscussionID, role: AIUsageRole) {
        let message = (error as? AIError)?.description ?? error.localizedDescription
        aiState = .failed(message)
        aiLastError = message
        appendMessage(String(format: InterfaceLanguage.label("（请求失败：%@）"), message), role: .system, to: discussionID)
        if case .modelUnavailable = (error as? AIError) {
            if let provider = ai.provider(for: role),
               let choice = ai.choice(for: role),
               !provider.defaultModel.isEmpty,
               choice.model != provider.defaultModel,
               provider.builtInModels.contains(provider.defaultModel) {
                ai.setRoleModel(role, model: provider.defaultModel)
                aiLastError = String(
                    format: InterfaceLanguage.label("已把「%@」切回默认模型 %@，重试即可。"),
                    InterfaceLanguage.label(role.displayName),
                    provider.defaultModel
                )
            }
            openAISettings()
        }
    }

    /// 采纳提案。给 `itemIDs` 就只落这一组，其余留在面板里继续选。
    func adoptPendingProposal(itemIDs: [String]? = nil) {
        commitAllTextDrafts()
        guard let validated = pendingProposal, let editor else { return }
        do {
            let count = try editor.adopt(validated, itemIDs: itemIDs)
            markEdited()
            refreshUndoAvailability()
            refreshDerived()
            saveState = .dirty
            scheduleAutosaveAfterAdoption()
            if let discussionID = aiDiscussionID {
                appendMessage(
                    String(format: InterfaceLanguage.label("已采纳 %lld 项改动。"), count),
                    role: .system,
                    to: discussionID
                )
            }
            aiLastError = nil

            let adopted = editor.adoptedItems(of: validated.proposal.id)
            let remaining = validated.acceptedItems.contains { !adopted.contains($0.id) }
            if !remaining {
                pendingProposal = nil
                showingProposalSheet = false
            }
        } catch {
            aiLastError = error.localizedDescription
        }
    }

    /// 这份提案里已经落地的项。
    var adoptedProposalItems: Set<String> {
        guard let validated = pendingProposal, let editor else { return [] }
        return editor.adoptedItems(of: validated.proposal.id)
    }

    func discardPendingProposal() {
        pendingProposal = nil
        showingProposalSheet = false
    }

    private func scheduleAutosaveAfterAdoption() {
        scheduleAutosave()
    }

    // MARK: 讨论持久化

    @discardableResult
    func ensureDiscussion() -> DiscussionID {
        if let aiDiscussionID, project?.discussions.contains(where: { $0.id == aiDiscussionID }) == true {
            return aiDiscussionID
        }
        guard let project else { return DiscussionID() }
        let discussion = Discussion(
            anchorNodeID: selectedNodeID,
            references: (liveContext?.references ?? []).map(Self.reference)
        )
        apply(ProjectMutations.appendDiscussion(discussion, to: project), name: "新建讨论")
        aiDiscussionID = discussion.id
        return discussion.id
    }

    func appendMessage(_ text: String, role: MessageRole, to discussionID: DiscussionID) {
        guard let project, !text.isEmpty else { return }
        apply(
            ProjectMutations.appendMessage(Message(role: role, text: text), to: discussionID, in: project),
            name: "记录讨论"
        )
    }

    /// 清空当前讨论的历史消息，保留讨论本身；一笔撤销可以找回。
    func clearAIDiscussion() {
        guard let project, let discussionID = aiDiscussionID else { return }
        apply(
            ProjectMutations.clearMessages(in: discussionID, in: project),
            name: "清空讨论记录"
        )
        aiLastError = nil
        if case .failed = aiState {
            aiState = .idle
        }
    }

    static func reference(_ reference: AIContext.Reference) -> DiscussionReference {
        switch reference.kind {
        case .node: .node(NodeID(rawValue: reference.rawID))
        case .edge: .chapter(ChapterID(rawValue: reference.rawID))
        case .setting: .setting(SettingID(rawValue: reference.rawID))
        case .character: .character(CharacterID(rawValue: reference.rawID))
        case .place: .place(PlaceID(rawValue: reference.rawID))
        case .asset: .node(NodeID(rawValue: reference.rawID))
        case .chapter: .chapter(ChapterID(rawValue: reference.rawID))
        }
    }
}


private extension AIRequestKind {
    /// 讨论/大纲走策划模型，改稿/插卡走写作模型。
    var usageRole: AIUsageRole {
        switch self {
        case .discussion, .outline: .planning
        case .editSelection, .insertCard: .writing
        }
    }
}
