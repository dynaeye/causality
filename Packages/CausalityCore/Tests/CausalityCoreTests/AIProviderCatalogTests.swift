import Testing
@testable import CausalityCore

@Suite("AI 服务目录")
struct AIProviderCatalogTests {
    @Test("内置服务包含新增的文本与图片入口")
    func builtInProviders() {
        let ids = Set(AIProvider.builtIn.map(\.id))
        #expect(ids.contains("chatgpt"))
        #expect(ids.contains("deepseek"))
        #expect(ids.contains("opencode-go"))
        #expect(ids.contains("openrouter"))
        #expect(ids.contains("kimi"))
        #expect(ids.contains("qwen"))
        #expect(ids.contains("gemini"))
        #expect(ids.contains("doubao"))
    }

    @Test("新服务的兼容端点")
    func endpoints() {
        #expect(AIProvider.qwen.endpointURL.absoluteString == "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
        #expect(AIProvider.gemini.endpointURL.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        #expect(AIProvider.doubao.endpointURL.absoluteString == "https://ark.cn-beijing.volces.com/api/v3/chat/completions")
        #expect(AIProvider.chatGPT.endpointURL.absoluteString == "https://chatgpt.com/backend-api/codex/responses")
    }
}
