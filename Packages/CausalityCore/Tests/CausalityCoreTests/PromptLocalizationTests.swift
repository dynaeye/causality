import Foundation
import Testing
@testable import CausalityCore

@Suite("提示词骨架本地化")
struct PromptLocalizationTests {
    private let english = CoreText.localizer(for: "en")

    @Test("system prompt 与分节标题走 localize")
    func promptUsesLocalizer() throws {
        let script = ConvergenceDemo.make()
        let context = PromptBuilder.makeContext(
            kind: .discussion,
            contextScope: .chapter,
            selection: script.askTownsfolk,
            project: script.project
        )
        let system = PromptBuilder.systemPrompt(for: .discussion, localize: english)
        #expect(system.hasPrefix("You are the story-planning assistant in Causality"))
        #expect(!system.contains("你是「因果」"))

        let message = PromptBuilder.userMessage(
            kind: .discussion,
            context: context,
            instruction: "tighten the first act",
            localize: english
        )
        #expect(message.contains("[Project]"))
        #expect(message.contains("[Scenes]"))
        #expect(message.contains("[The author’s request this round]"))
    }
}
