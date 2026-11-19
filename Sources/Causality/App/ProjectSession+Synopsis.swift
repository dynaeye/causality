import AppKit
import Foundation
import CausalityCore
import UniformTypeIdentifiers

// MARK: - 分支梗概

extension ProjectSession {
    func openSynopsis() {
        guard project != nil else { return }
        isWriting = false
        isAuditing = false
        isSynopsizing = true
        refreshSynopsis()
    }

    func closeSynopsis() {
        isSynopsizing = false
    }

    func setSynopsisMode(_ mode: BranchSynopsis.Mode) {
        synopsisMode = mode
        refreshSynopsis()
    }

    func refreshSynopsis() {
        guard let project else {
            synopsisGroups = []
            return
        }
        synopsisGroups = BranchSynopsis.endings(in: project).map { ending in
            BranchSynopsis.make(project: project, endingID: ending.id, mode: synopsisMode)
        }
    }

    /// 润色只落面板：键是这一块的节点序列 + 当前 revision，任何一张卡被改就查不到旧结果。
    func synopsisPolishKey(_ block: BranchBlock) -> String {
        Self.synopsisPolishKey(block: block, revision: project?.revision ?? -1)
    }

    private static func synopsisPolishKey(block: BranchBlock, revision: Int) -> String {
        let ids = block.nodeIDs.map(\.rawValue.uuidString).joined(separator: ",")
        return "\(ids)@\(revision)"
    }

    func polishSynopsis(_ block: BranchBlock) {
        let key = synopsisPolishKey(block)
        guard !synopsisPolishing.contains(key) else { return }
        guard let project else { return }
        guard let choice = ai.choice(for: .planning),
              let roleProvider = ai.provider(id: choice.providerID),
              !choice.model.isEmpty else {
            synopsisPolishErrors[key] = InterfaceLanguage.label("先在 AI 设置里给「策划 / 大纲」选一个模型。")
            return
        }
        guard let credential = ai.loadCredential(for: roleProvider.id) else {
            synopsisPolishErrors[key] = String(format: InterfaceLanguage.label("还没有配置 %@ 的 API key，先在 AI 设置里填。"), roleProvider.localizedDisplayName)
            return
        }

        let facts = block.nodeIDs.compactMap { project.node($0) }.map { node -> String in
            var parts = [String(format: InterfaceLanguage.label("「%@」"), node.title)]
            if let pov = node.pov,
               let name = project.characters.first(where: { $0.id == pov })?.name {
                parts.append(String(format: InterfaceLanguage.label("视角：%@"), name))
            }
            if !node.storyTimeLabel.isEmpty {
                parts.append(String(format: InterfaceLanguage.label("时间：%@"), node.storyTimeLabel))
            }
            if let tension = node.tension {
                parts.append(String(format: InterfaceLanguage.label("张力：%lld/5"), tension))
            }
            return parts.joined(separator: "｜")
        }

        let request = AIRequest(
            provider: roleProvider,
            model: choice.model,
            systemPrompt: "你在帮编剧润色分支梗概。保持事实、顺序与人物不变；用四句以内的中文；不写正文细节，不新增原文没有的情节；只输出润色后的梗概。",
            userMessage: """
            原文：
            \(block.text)

            场景资料：
            \(facts.joined(separator: "\n"))
            """,
            maxOutputTokens: 2400,
            temperature: 0.3,
            sessionID: aiSessionID
        )

        synopsisPolishing.insert(key)
        synopsisPolishErrors[key] = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let completion = try await self.aiClient.complete(request, credential: credential)
                let text = completion.text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.synopsisPolish[key] = text.isEmpty ? nil : text
                if text.isEmpty {
                    let note = completion.note.map { "（\($0)）" } ?? ""
                    self.synopsisPolishErrors[key] = String(format: InterfaceLanguage.label("这次没有拿到可用的文字，再试一次。%@"), note)
                }
            } catch {
                self.synopsisPolishErrors[key] = error.localizedDescription
            }
            self.synopsisPolishing.remove(key)
        }
    }

    func exportSynopsisMarkdown() {
        guard let project else { return }
        let language = workLanguage
        // 导出按作品语言重排结构标签；界面上的分支梗概仍跟界面语言。
        let groups = BranchSynopsis.endings(in: project).map { ending in
            BranchSynopsis.make(
                project: project,
                endingID: ending.id,
                mode: synopsisMode,
                localize: language.label
            )
        }
        let polish = synopsisPolish
        let revision = project.revision
        let title = project.title
        Task {
            commitAllTextDrafts()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.nameFieldStringValue = "\(title)-\(language.label("分支梗概")).md"
            guard let url = await FilePanels.url(panel) else { return }

            var lines = [String(format: language.label("# %@ · 分支梗概"), title), ""]
            for group in groups {
                lines.append(String(format: language.label("## 结局 · %@"), group.endingTitle))
                lines.append(
                    String(
                        format: language.label("- 卡数 %lld · 字数 %lld · 选择点 %lld · 独占卡 %lld"),
                        group.cardCount,
                        group.stats.wordCount,
                        group.stats.choiceCount,
                        group.stats.exclusiveCount
                    )
                )
                if let shortest = group.stats.shortestSteps, let longest = group.stats.longestSteps {
                    lines.append(String(format: language.label("- 最短 %lld 步 · 最长 %lld 步"), shortest, longest))
                }
                lines.append("")
                for block in group.blocks {
                    let key = Self.synopsisPolishKey(block: block, revision: revision)
                    lines.append("### \(block.label)")
                    lines.append(polish[key] ?? block.text(localize: language.label))
                    lines.append("")
                }
            }
            do {
                try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
