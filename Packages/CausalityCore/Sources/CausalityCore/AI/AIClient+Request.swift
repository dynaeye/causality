import Foundation

/// 请求体构造与错误映射。
extension AIClient {
    // MARK: 请求构造

    func build(_ request: AIRequest, credential: AICredential) throws -> URLRequest {
        var urlRequest = URLRequest(url: request.provider.endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(credential.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(request.provider.userAgent, forHTTPHeaderField: "User-Agent")
        if request.provider.requiresSessionHeader {
            urlRequest.setValue(request.sessionID, forHTTPHeaderField: "x-opencode-session")
        }
        if request.provider.id == AIProvider.chatGPT.id {
            urlRequest.setValue(request.sessionID, forHTTPHeaderField: "session_id")
            urlRequest.setValue("causality", forHTTPHeaderField: "originator")
            urlRequest.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
            if let accountID = credential.accountID {
                urlRequest.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
            }
        }

        var body: [String: Any] = [:]
        switch request.provider.apiStyle {
        case .chatCompletions:
            body["model"] = request.model
            body["stream"] = true
            body["max_tokens"] = request.provider.clampOutputTokens(request.maxOutputTokens)
            body["temperature"] = request.temperature
            var messages: [[String: String]] = [
                ["role": "system", "content": request.systemPrompt]
            ]
            messages += request.history.map { turn in
                ["role": turn.role.rawValue, "content": turn.text]
            }
            messages.append(["role": "user", "content": request.userMessage])
            body["messages"] = messages
            if let schema = request.jsonSchema {
                if request.provider.supportsStructuredOutput {
                    body["response_format"] = [
                        "type": "json_schema",
                        "json_schema": [
                            "name": ProposalSchema.name,
                            "strict": true,
                            "schema": try parseSchema(schema)
                        ]
                    ]
                } else if request.provider.supportsJSONMode {
                    body["response_format"] = ["type": "json_object"]
                }
            }

        case .responses:
            body["model"] = request.model
            body["stream"] = true
            body["store"] = false
            body["instructions"] = request.systemPrompt
            var input: [[String: Any]] = request.history.map { turn in
                [
                    "role": turn.role.rawValue,
                    "content": [["type": turn.role == .user ? "input_text" : "output_text", "text": turn.text]]
                ]
            }
            input.append([
                "role": "user",
                "content": [["type": "input_text", "text": request.userMessage]]
            ])
            body["input"] = input
            body["max_output_tokens"] = request.provider.clampOutputTokens(request.maxOutputTokens)
            var textConfig: [String: Any] = [:]
            if let schema = request.jsonSchema, request.provider.supportsStructuredOutput {
                textConfig["format"] = [
                    "type": "json_schema",
                    "name": ProposalSchema.name,
                    "strict": true,
                    "schema": try parseSchema(schema)
                ]
            } else {
                textConfig["format"] = ["type": "text"]
            }
            body["text"] = textConfig
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    func parseSchema(_ json: String) throws -> Any {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            throw AIError.unsupported("内置 JSON Schema 无法解析")
        }
        return object
    }

    func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard http.statusCode != 200 else { return }
        let message = Self.snippet(body)
        // `where` 只挂在最后一个模式上：拆开写，400 的参数错误才不会被当成模型下线。
        if [400, 403, 404].contains(http.statusCode), Self.isModelUnavailable(message) {
            throw AIError.modelUnavailable(
                "模型不可用（\(message)）。多半是这个 ID 已下线或未对当前账号开放，换一个模型再试。"
            )
        }
        switch http.statusCode {
        case 401, 403:
            throw AIError.unauthorized(message)
        case 429:
            throw AIError.quotaExhausted(message)
        default:
            throw AIError.http(status: http.statusCode, message: message)
        }
    }

    static func isModelUnavailable(_ message: String) -> Bool {
        let lower = message.lowercased()
        return message.contains("RegionError")
            || lower.contains("not available in your country")
            || lower.contains("model is unavailable")
            || lower.contains("model not found")
    }

    static func snippet(_ data: Data) -> String {
        let text = String(bytes: data.prefix(600), encoding: .utf8) ?? ""
        return text.replacingOccurrences(of: "\n", with: " ")
    }
}
