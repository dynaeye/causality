import Foundation

/// 一家服务的 HTTP 客户端。请求可取消，回复按行流式读回。
public actor AIClient {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    /// 流式调用。取消这个流即取消底层请求。
    ///
    /// 一条流在收到第一个字之前失败会自动重发（连接被复用后失效、切网、网关 5xx 都属于这一类）；
    /// 已经吐字之后再断，就把已收到的部分作为正常收尾交出去，附一句说明。
    public func stream(_ request: AIRequest, credential: AICredential) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var attempt = 0
                var receivedText = false
                while true {
                    do {
                        let completion = try await self.run(request, credential: credential) { delta in
                            receivedText = true
                            continuation.yield(.textDelta(delta))
                        }
                        continuation.yield(.completed(completion))
                        continuation.finish()
                        return
                    } catch is CancellationError {
                        continuation.finish(throwing: AIError.cancelled)
                        return
                    } catch {
                        let mapped = AIRetry.map(error)
                        let canRetry = !receivedText
                            && AIRetry.isTransient(mapped)
                            && attempt + 1 < AIRetry.maxAttempts
                        guard canRetry else {
                            continuation.finish(throwing: mapped)
                            return
                        }
                        attempt += 1
                        try? await Task.sleep(for: AIRetry.delay(after: attempt - 1))
                        if Task.isCancelled {
                            continuation.finish(throwing: AIError.cancelled)
                            return
                        }
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 一次性拿到完整回复。调用方取消 Task 即取消请求。
    ///
    /// 只收正文、没收到正事收尾帧的响应不算格式错误：把已经收到的正文交出去，标成 interrupted。
    public func complete(_ request: AIRequest, credential: AICredential) async throws -> AICompletion {
        var text = ""
        var final: AICompletion?
        for try await event in stream(request, credential: credential) {
            switch event {
            case let .textDelta(delta):
                text += delta
            case let .completed(completion):
                final = completion
            }
        }
        if var completion = final {
            if !text.isEmpty { completion.text = text }
            return completion
        }
        if !text.isEmpty {
            return AICompletion(
                text: text,
                model: request.model,
                providerID: request.provider.id,
                finishReason: "interrupted",
                note: CoreText.text("服务没有发出收尾帧，下面是已经收到的部分。")
            )
        }
        throw AIError.malformedOutput(CoreText.text("服务返回了空回复：既没有正文也没有收尾帧。重发一次；连着出现就换个服务或模型。"))
    }

    /// 列出模型目录，用于联调时确认模型 ID。
    public func listModels(provider: AIProvider, credential: AICredential) async throws -> [String] {
        guard credential.isUsable else { throw AIError.missingCredential }
        guard let modelsPath = provider.modelsPath else {
            throw AIError.unsupported(CoreText.text("这家服务不提供模型目录"))
        }
        let root = provider.modelsBaseURL ?? provider.baseURL
        var request = URLRequest(url: root.appendingPathComponent(modelsPath))
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credential.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(provider.userAgent, forHTTPHeaderField: "User-Agent")

        var attempt = 0
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                try validate(response: response, body: data)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rows = object["data"] as? [[String: Any]] else {
                    return []
                }
                return rows.compactMap { $0["id"] as? String }.sorted()
            } catch {
                let mapped = AIRetry.map(error)
                guard AIRetry.isTransient(mapped), attempt + 1 < AIRetry.maxAttempts else {
                    throw mapped
                }
                attempt += 1
                try? await Task.sleep(for: AIRetry.delay(after: attempt - 1))
            }
        }
    }

    // MARK: 主流程

    /// 发一次请求，返回收尾时拼出来的完整回复。正文增量走 onDelta。
    private func run(
        _ request: AIRequest,
        credential: AICredential,
        onDelta: (String) -> Void
    ) async throws -> AICompletion {
        guard credential.isUsable else { throw AIError.missingCredential }
        let urlRequest = try build(request, credential: credential)
        let budget = request.provider.clampOutputTokens(request.maxOutputTokens)

        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.transport(CoreText.text("没有拿到 HTTP 响应"))
        }
        if http.statusCode != 200 {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 4096 { break }
            }
            try validate(response: response, body: body)
            throw AIError.http(status: http.statusCode, message: String(bytes: body, encoding: .utf8) ?? "")
        }

        var state = StreamState()
        do {
            try await consume(bytes: bytes, request: request, state: &state, onDelta: onDelta)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let mapped = AIRetry.map(error)
            // 已经吐字了就不丢：把收到的部分交出去，注明断在哪。
            if !state.text.isEmpty {
                return finish(
                    state,
                    request: request,
                    finishReason: "interrupted",
                    note: CoreText.format("连接中途断了（%@）。下面是已经收到的部分。", mapped.description)
                )
            }
            throw mapped
        }

        if let message = state.errorMessage {
            if !state.text.isEmpty {
                return finish(
                    state,
                    request: request,
                    finishReason: "interrupted",
                    note: CoreText.format("服务在流里报错：%@。下面是已经收到的部分。", message)
                )
            }
            throw AIError.transport(CoreText.format("服务在流里报错：%@", message))
        }

        return finish(state, request: request, finishReason: state.finishReason, note: note(for: state.finishReason, budget: budget, state: state))
    }

    private func finish(
        _ state: StreamState,
        request: AIRequest,
        finishReason: String?,
        note: String?
    ) -> AICompletion {
        AICompletion(
            text: state.text,
            model: request.model,
            providerID: request.provider.id,
            inputTokens: state.inputTokens,
            outputTokens: state.outputTokens,
            finishReason: finishReason,
            note: note
        )
    }

    /// 收尾原因翻成一句作者能行动的话。
    private func note(for finishReason: String?, budget: Int, state: StreamState) -> String? {
        switch finishReason {
        case "length", "max_tokens":
            if state.text.isEmpty {
                let used = state.outputTokens.map { CoreText.format("，服务报用掉 %lld", $0) } ?? ""
                return CoreText.format(
                    "输出预算 %lld tokens 在写出正文之前就用完了%@——思考过程也算在这里面。已自动加重预算重试仍不够，这一轮要处理的卡太多了。",
                    budget, used
                )
            }
            return CoreText.format("回复撞到 %lld tokens 的输出上限，后面的内容没写完。", budget)
        case "incomplete":
            return CoreText.text("服务把这条回复标成未完成（可能触发了内容过滤，或到了输出上限）。")
        default:
            return nil
        }
    }

    struct StreamState {
        var text = ""
        var finishReason: String?
        var inputTokens: Int?
        var outputTokens: Int?
        /// 流里夹带的错误。正文为空时据此抛错，有正文时保留正文并附一句说明。
        var errorMessage: String?
    }

    private func consume(
        bytes: URLSession.AsyncBytes,
        request: AIRequest,
        state: inout StreamState,
        onDelta: (String) -> Void
    ) async throws {
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty || payload == "[DONE]" { continue }
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            try apply(object, request: request, state: &state, onDelta: onDelta)
        }
    }

    private func apply(
        _ object: [String: Any],
        request: AIRequest,
        state: inout StreamState,
        onDelta: (String) -> Void
    ) throws {
        let parsed: ParsedChunk
        switch request.provider.apiStyle {
        case .chatCompletions:
            parsed = parseChatChunk(object)
        case .responses:
            parsed = parseResponsesEvent(object)
        }
        if let delta = parsed.delta {
            state.text += delta
            onDelta(delta)
        }
        state.finishReason = parsed.finishReason ?? state.finishReason
        state.inputTokens = parsed.inputTokens ?? state.inputTokens
        state.outputTokens = parsed.outputTokens ?? state.outputTokens
        state.errorMessage = parsed.errorMessage ?? state.errorMessage
    }
}
