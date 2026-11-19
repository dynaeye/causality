import Foundation

/// SSE 分片解析。
extension AIClient {
    // MARK: 分片解析

    struct ParsedChunk {
        var delta: String?
        var finishReason: String?
        var inputTokens: Int?
        var outputTokens: Int?
        /// 分片里带的错误说明。有它就说明这一轮不会再有正文了。
        var errorMessage: String?
    }

    func parseChatChunk(_ object: [String: Any]) -> ParsedChunk {
        var parsed = ParsedChunk()
        if let message = Self.errorMessage(in: object) {
            parsed.errorMessage = message
            return parsed
        }
        if let choices = object["choices"] as? [[String: Any]], let choice = choices.first {
            if let delta = choice["delta"] as? [String: Any], let content = delta["content"] as? String {
                parsed.delta = content
            }
            if let reason = choice["finish_reason"] as? String {
                parsed.finishReason = reason
            }
        }
        if let usage = object["usage"] as? [String: Any] {
            parsed.inputTokens = usage["prompt_tokens"] as? Int
            parsed.outputTokens = usage["completion_tokens"] as? Int
        }
        return parsed
    }

    func parseResponsesEvent(_ object: [String: Any]) -> ParsedChunk {
        var parsed = ParsedChunk()
        let type = object["type"] as? String ?? ""
        switch type {
        case "response.output_text.delta":
            parsed.delta = object["delta"] as? String
        case "response.completed":
            if let response = object["response"] as? [String: Any] {
                parsed.finishReason = response["status"] as? String
                if let usage = response["usage"] as? [String: Any] {
                    parsed.inputTokens = usage["input_tokens"] as? Int
                    parsed.outputTokens = usage["output_tokens"] as? Int
                }
            }
        case "response.incomplete":
            parsed.finishReason = "incomplete"
            if let response = object["response"] as? [String: Any],
               let details = response["incomplete_details"] as? [String: Any],
               let reason = details["reason"] as? String {
                parsed.errorMessage = nil
                parsed.finishReason = reason == "max_output_tokens" ? "length" : "incomplete"
            }
        case "error", "response.failed":
            parsed.errorMessage = Self.errorMessage(in: object) ?? CoreText.text("服务没有给出原因")
        default:
            if let message = Self.errorMessage(in: object) {
                parsed.errorMessage = message
            }
        }
        return parsed
    }

    /// 从分片里掏出错误说明。两家服务的形状不一样，统一在这里认。
    static func errorMessage(in object: [String: Any]) -> String? {
        if let error = object["error"] as? [String: Any] {
            let text = (error["message"] as? String) ?? (error["code"] as? String)
            return text ?? CoreText.text("服务返回了错误但没有说明")
        }
        if let error = object["error"] as? String, !error.isEmpty {
            return error
        }
        if let message = object["message"] as? String,
           (object["type"] as? String)?.hasSuffix("error") == true || object["base_resp"] != nil {
            return message
        }
        if let base = object["base_resp"] as? [String: Any],
           let status = base["status_code"] as? Int, status != 0 {
            let text = base["status_msg"] as? String ?? ""
            return text.isEmpty ? CoreText.format("服务返回状态 %lld", status) : text
        }
        return nil
    }
}
