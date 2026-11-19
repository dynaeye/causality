import Foundation
import Testing
@testable import CausalityCore

@Suite("AI 稳定性：预算、截断与断线")
struct AIStabilityTests {
    // MARK: 预算

    @Test("预算按服务上限压回来")
    func clampBudget() {
        #expect(AIProvider.openCodeGo.clampOutputTokens(8000) == 8000)
        #expect(AIProvider.openCodeGo.clampOutputTokens(64000) == 32000)
        #expect(AIProvider.deepSeek.clampOutputTokens(32000) == 8192)
        #expect(AIProvider.deepSeek.clampOutputTokens(1) == 256)
    }

    @Test("提案默认预算够写一章的卡片清单")
    func defaultBudget() {
        #expect(ProposalRequest(kind: .outline, instruction: "", provider: .openCodeGo, model: "glm-5.3", credential: AICredential(apiKey: "k")).maxOutputTokens >= 8000)
    }

    // MARK: 截断

    @Test("撞到上限和未完成都算截断，断流不算")
    func truncationKinds() {
        let length = AICompletion(text: "", model: "m", providerID: "p", finishReason: "length")
        let incomplete = AICompletion(text: "", model: "m", providerID: "p", finishReason: "incomplete")
        let interrupted = AICompletion(text: "半句", model: "m", providerID: "p", finishReason: "interrupted")
        let normal = AICompletion(text: "写完", model: "m", providerID: "p", finishReason: "stop")

        #expect(length.isTruncated)
        #expect(incomplete.isTruncated)
        #expect(!interrupted.isTruncated)
        #expect(interrupted.isInterrupted)
        #expect(!normal.isTruncated)
    }

    @Test("只有预算不够才值得加预算重试")
    func wantsMoreBudget() {
        #expect(ProposalService.wantsMoreBudget(AICompletion(text: "", model: "m", providerID: "p", finishReason: "length")))
        #expect(ProposalService.wantsMoreBudget(AICompletion(text: "", model: "m", providerID: "p", finishReason: "stop")))
        #expect(!ProposalService.wantsMoreBudget(AICompletion(text: "断线前的正文", model: "m", providerID: "p", finishReason: "interrupted")))
        #expect(!ProposalService.wantsMoreBudget(AICompletion(text: "{}", model: "m", providerID: "p", finishReason: "stop")))
    }

    @Test("截断提示说清预算与实际用量")
    func truncationMessage() {
        let empty = ProposalService.truncated(
            budget: 4200,
            completion: AICompletion(text: "", model: "glm-5.3", providerID: "opencode-go", outputTokens: 4200, finishReason: "length")
        )
        #expect(empty.description.contains("4200"))
        #expect(empty.description.contains("思考"))

        let partial = ProposalService.truncated(
            budget: 8000,
            completion: AICompletion(text: "{\"summary\":", model: "m", providerID: "p", finishReason: "length")
        )
        #expect(partial.description.contains("写了一半"))
    }

    // MARK: 分片里的错误

    @Test("聊天分片里的 error 会被认出来")
    func chatChunkError() async {
        let client = AIClient()
        let chunk = await client.parseChatChunk(["error": ["message": "upstream overloaded"]])
        #expect(chunk.errorMessage == "upstream overloaded")
        #expect(chunk.delta == nil)
    }

    @Test("MiniMax 的 base_resp 状态也算错误")
    func miniMaxError() {
        let message = AIClient.errorMessage(in: [
            "base_resp": ["status_code": 1004, "status_msg": "invalid api key"],
        ])
        #expect(message == "invalid api key")
    }

    @Test("正常分片不报错")
    func normalChunk() async {
        let client = AIClient()
        let chunk = await client.parseChatChunk([
            "choices": [["delta": ["content": "阿禾"], "finish_reason": NSNull()]],
        ])
        #expect(chunk.delta == "阿禾")
        #expect(chunk.errorMessage == nil)
    }

    // MARK: 重试判定

    @Test("断网、超时、5xx 值得重发")
    func transientErrors() {
        #expect(AIRetry.isTransient(URLError(.networkConnectionLost)))
        #expect(AIRetry.isTransient(URLError(.timedOut)))
        #expect(AIRetry.isTransient(AIError.http(status: 503, message: "bad gateway")))
        #expect(AIRetry.isTransient(AIError.transport("断了")))
    }

    @Test("鉴权与模型问题重发没用")
    func permanentErrors() {
        #expect(!AIRetry.isTransient(AIError.unauthorized("401")))
        #expect(!AIRetry.isTransient(AIError.modelUnavailable("下线了")))
        #expect(!AIRetry.isTransient(AIError.missingCredential))
    }

    @Test("URLError 翻成能行动的中文")
    func errorMapping() {
        #expect(AIRetry.map(URLError(.timedOut)) == .timeout)
        #expect(AIRetry.map(URLError(.cancelled)) == .cancelled)
        if case let .transport(reason) = AIRetry.map(URLError(.networkConnectionLost)) {
            #expect(reason.contains("重发"))
        }
    }

    // MARK: 提示词

    @Test("提示词里标出场景与灵感卡")
    func nodeStatusMarker() {
        let script = ConvergenceDemo.make()
        let project = script.project
        let context = PromptBuilder.makeContext(
            kind: .outline,
            contextScope: .chapter,
            selection: script.askTownsfolk,
            project: project
        )
        let message = PromptBuilder.userMessage(kind: .outline, context: context, instruction: "理顺第一章")
        #expect(message.contains("｜场景｜"))
        #expect(message.contains("灵感卡") == false)
        #expect(PromptBuilder.systemPrompt(for: .outline).contains("灵感卡"))
    }

    // MARK: HTTP 错误分类

    private func validationError(status: Int, body: String) async -> AIError? {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/v1/chat/completions")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        do {
            try await AIClient().validate(response: response, body: Data(body.utf8))
            return nil
        } catch let error as AIError {
            return error
        } catch {
            return nil
        }
    }

    @Test("400 的参数错误不会被当成模型下线")
    func parameterErrorIsNotModelUnavailable() async {
        let error = await validationError(
            status: 400,
            body: #"{"error":{"message":"max_tokens: must be less than or equal to 8192"}}"#
        )
        guard case let .http(status, message)? = error else {
            Issue.record("期望 http 错误，实际 \(String(describing: error))")
            return
        }
        #expect(status == 400)
        #expect(message.contains("max_tokens"))
    }

    @Test("模型确实不可用时，400 / 403 / 404 都归到同一类")
    func modelUnavailableSamples() async {
        let samples: [(Int, String)] = [
            (400, #"{"error":{"message":"model not found"}}"#),
            (403, #"{"error":{"message":"RegionError: not available in your country"}}"#),
            (404, #"{"error":{"message":"The model is unavailable"}}"#),
        ]
        for (status, body) in samples {
            guard case .modelUnavailable? = await validationError(status: status, body: body) else {
                Issue.record("\(status) 应该报模型不可用：\(body)")
                continue
            }
        }
    }

    @Test("403 的权限错误仍然按凭据问题处理")
    func forbiddenStaysUnauthorized() async {
        guard case .unauthorized? = await validationError(status: 403, body: #"{"error":{"message":"permission denied"}}"#) else {
            Issue.record("403 权限错误应报 unauthorized")
            return
        }
    }
}
