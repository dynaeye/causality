import Foundation

public enum JSONExtraction {
    /// 从模型回复里取出第一个 JSON 对象。允许前后有说明文字或 markdown 代码块。
    public static func firstObject(in text: String) -> Data? {
        if let fenced = fencedBlock(in: text) {
            return Data(fenced.utf8)
        }
        guard let range = balancedObjectRange(in: text) else { return nil }
        return Data(text[range].utf8)
    }

    private static func fencedBlock(in text: String) -> String? {
        guard let start = text.range(of: "```") else { return nil }
        var rest = text[start.upperBound...]
        if rest.hasPrefix("json") {
            rest = rest.dropFirst(4)
        }
        guard let end = rest.range(of: "```") else { return nil }
        let body = rest[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.hasPrefix("{") else { return nil }
        return body
    }

    private static func balancedObjectRange(in text: String) -> Range<String.Index>? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                switch character {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        return start ..< text.index(after: index)
                    }
                default: break
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

public enum ProposalParsing {
    public static func decodePayload(from text: String) throws -> ProposalPayload {
        guard let data = JSONExtraction.firstObject(in: text) else {
            throw AIError.malformedOutput(CoreText.text("回复里没有 JSON 对象"))
        }
        do {
            return try JSONDecoder().decode(ProposalPayload.self, from: data)
        } catch {
            throw AIError.malformedOutput(CoreText.format("提案字段不完整：%@", "\(error)"))
        }
    }

    /// 把模型产出包成 App 侧提案，并记下发起时的版本快照。
    public static func makeProposal(
        payload: ProposalPayload,
        project: StoryProject,
        scope: ProposalScope
    ) -> AIProposal {
        var revisions: [NodeID: Int] = [:]
        for nodeID in scope.editableNodeIDs {
            if let node = project.node(nodeID) {
                revisions[nodeID] = node.revision
            }
        }
        return AIProposal(
            baseRevision: project.revision,
            nodeRevisions: revisions,
            payload: payload
        )
    }
}

public struct ProposalRequest: Sendable {
    public var kind: AIRequestKind
    public var instruction: String
    public var contextScope: AIContextScope
    public var selection: NodeID?
    public var provider: AIProvider
    public var model: String
    public var credential: AICredential
    public var excludedReferences: Set<String>
    public var maxOutputTokens: Int
    /// 故事板上“这里”的位置。kind 为 insertCard 时用它决定落在哪。
    public var insertion: CardInsertionPoint?
    /// 之前几轮对话，按时间顺序。
    public var history: [AIChatTurn]

    public init(
        kind: AIRequestKind,
        instruction: String,
        contextScope: AIContextScope = .selection,
        selection: NodeID? = nil,
        provider: AIProvider,
        model: String,
        credential: AICredential,
        excludedReferences: Set<String> = [],
        history: [AIChatTurn] = [],
        maxOutputTokens: Int = 8000,
        insertion: CardInsertionPoint? = nil
    ) {
        self.kind = kind
        self.instruction = instruction
        self.contextScope = contextScope
        self.selection = selection
        self.provider = provider
        self.model = model
        self.credential = credential
        self.excludedReferences = excludedReferences
        self.history = history
        self.maxOutputTokens = maxOutputTokens
        self.insertion = insertion
    }

    public var effectiveModel: String {
        model.isEmpty ? provider.defaultModel : model
    }
}

public struct ProposalResult: Sendable {
    public var request: ProposalRequest
    public var context: AIContext
    public var scope: ProposalScope
    public var completion: AICompletion
    public var validated: ValidatedProposal?
    public var parseFailure: String?

    public var rawText: String { completion.text }
}

/// 把“上下文 → 请求 → 解析 → 校验”串起来。界面与联调命令都用它。
public actor ProposalService {
    private let client: AIClient

    public init(client: AIClient = AIClient()) {
        self.client = client
    }

    public func run(
        _ request: ProposalRequest,
        project: StoryProject,
        localize: @Sendable (String) -> String = { $0 }
    ) async throws -> ProposalResult {
        let context = PromptBuilder.makeContext(
            kind: request.kind,
            contextScope: request.contextScope,
            selection: request.selection,
            project: project,
            insertion: request.insertion,
            excluded: request.excludedReferences
        )
        let scope = Self.makeScope(request: request, project: project)

        var budget = request.maxOutputTokens
        var completion = try await complete(request, context: context, budget: budget, localize: localize)

        guard request.kind.producesProposal else {
            return ProposalResult(
                request: request,
                context: context,
                scope: scope,
                completion: completion,
                validated: nil,
                parseFailure: nil
            )
        }

        var outcome = parse(completion, request: request, project: project, scope: scope)

        // 截断或空正文，多半是预算撑不住：加一倍以上再试一次。
        if outcome.validated == nil, Self.wantsMoreBudget(completion) {
            let bigger = request.provider.clampOutputTokens(max(budget * 3, budget + 4000))
            if bigger > budget {
                budget = bigger
                completion = try await complete(request, context: context, budget: bigger, localize: localize)
                outcome = parse(completion, request: request, project: project, scope: scope)
            }
        }

        if outcome.validated == nil, completion.isTruncated {
            throw Self.truncated(budget: budget, completion: completion)
        }

        return ProposalResult(
            request: request,
            context: context,
            scope: scope,
            completion: completion,
            validated: outcome.validated,
            parseFailure: outcome.failure
        )
    }

    private func complete(
        _ request: ProposalRequest,
        context: AIContext,
        budget: Int,
        localize: @Sendable (String) -> String
    ) async throws -> AICompletion {
        let aiRequest = AIRequest(
            provider: request.provider,
            model: request.effectiveModel,
            systemPrompt: PromptBuilder.systemPrompt(for: request.kind, localize: localize),
            userMessage: PromptBuilder.userMessage(
                kind: request.kind,
                context: context,
                instruction: request.instruction,
                localize: localize
            ),
            jsonSchema: request.kind.producesProposal ? ProposalSchema.json : nil,
            maxOutputTokens: budget,
            sessionID: request.credential.sessionID
        )
        return try await client.complete(aiRequest, credential: request.credential)
    }

    private func parse(
        _ completion: AICompletion,
        request: ProposalRequest,
        project: StoryProject,
        scope: ProposalScope
    ) -> (validated: ValidatedProposal?, failure: String?) {
        do {
            let payload = try ProposalParsing.decodePayload(from: completion.text)
            let proposal = ProposalParsing.makeProposal(payload: payload, project: project, scope: scope)
            return (ProposalValidator.validate(proposal, in: project, scope: scope), nil)
        } catch {
            return (nil, (error as? AIError)?.description ?? String(describing: error))
        }
    }

    /// 预算不够的两种表现：撞到上限，或者思考把额度吃光、正文一个字没写。
    static func wantsMoreBudget(_ completion: AICompletion) -> Bool {
        if completion.isTruncated { return true }
        return completion.text.isEmpty && !completion.isInterrupted
    }

    static func truncated(budget: Int, completion: AICompletion) -> AIError {
        var text = CoreText.format("回复被截断（输出预算 %lld tokens", budget)
        if let used = completion.outputTokens {
            text += CoreText.format("，服务报用掉 %lld", used)
        }
        text += CoreText.text(completion.text.isEmpty
            ? "）：思考把额度吃光了，正文一个字也没写出来。"
            : "）：提案写了一半。")
        text += CoreText.text(completion.text.isEmpty
            ? "这个模型思考很费 token：换一个思考少的模型，或把范围收到几张卡再跑。"
            : "把范围收到本章的几张卡，或先用「讨论」把思路理清，再让它整理成大纲。")
        return .truncated(text)
    }

    /// 讨论用流式回复。取消这个流即取消请求。
    public func streamDiscussion(
        _ request: ProposalRequest,
        project: StoryProject,
        localize: @Sendable (String) -> String = { $0 }
    ) async -> AsyncThrowingStream<AIStreamEvent, Error> {
        let context = PromptBuilder.makeContext(
            kind: .discussion,
            contextScope: request.contextScope,
            selection: request.selection,
            project: project,
            insertion: request.insertion,
            excluded: request.excludedReferences
        )
        let aiRequest = AIRequest(
            provider: request.provider,
            model: request.effectiveModel,
            systemPrompt: PromptBuilder.systemPrompt(for: .discussion, localize: localize),
            userMessage: PromptBuilder.userMessage(
                kind: .discussion,
                context: context,
                instruction: request.instruction,
                localize: localize
            ),
            history: request.history,
            jsonSchema: nil,
            maxOutputTokens: request.maxOutputTokens,
            temperature: 0.7,
            sessionID: request.credential.sessionID
        )
        return await client.stream(aiRequest, credential: request.credential)
    }

    public static func makeScope(request: ProposalRequest, project: StoryProject) -> ProposalScope {
        if request.kind == .insertCard, let insertion = request.insertion {
            return .insertion(chapterID: insertion.chapterID, index: insertion.index, in: project)
        }
        switch request.contextScope {
        case .selection:
            guard let selection = request.selection else {
                return .wholeProject(project)
            }
            return .selection(nodeID: selection, in: project)
        case .chapter:
            let chapterID = request.selection.flatMap { project.node($0)?.chapterID }
                ?? project.chapters.first?.id
            guard let chapterID else { return .wholeProject(project) }
            return .chapter(chapterID, in: project)
        case .project:
            return .wholeProject(project)
        }
    }
}
