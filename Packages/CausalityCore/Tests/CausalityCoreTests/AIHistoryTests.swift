import Foundation
import Testing
@testable import CausalityCore

@Suite("讨论历史进请求")
struct AIHistoryTests {
    private func credential() -> AICredential {
        AICredential(apiKey: "test-key", sessionID: "session")
    }

    @Test("历史按顺序插在 system 与当前 user 之间")
    @MainActor
    func chatCompletionsCarriesHistory() async throws {
        let client = AIClient()
        let request = AIRequest(
            provider: .openCodeGo,
            model: "glm-5.3",
            systemPrompt: "系统提示",
            userMessage: "第六轮问题",
            history: [
                AIChatTurn(role: .user, text: "第一轮问题"),
                AIChatTurn(role: .assistant, text: "第一轮回答"),
            ]
        )
        let urlRequest = try await client.build(request, credential: credential())
        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.count == 4)
        #expect(messages[0]["role"] == "system")
        #expect(messages[1]["content"] == "第一轮问题")
        #expect(messages[2]["role"] == "assistant")
        #expect(messages[3]["content"] == "第六轮问题")
    }

    @Test("没有历史时保持原来两条")
    @MainActor
    func noHistory() async throws {
        let client = AIClient()
        let request = AIRequest(
            provider: .openCodeGo,
            model: "glm-5.3",
            systemPrompt: "系统提示",
            userMessage: "问题"
        )
        let body = try #require(try await client.build(request, credential: credential()).httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect((json["messages"] as? [[String: String]])?.count == 2)
    }
}
