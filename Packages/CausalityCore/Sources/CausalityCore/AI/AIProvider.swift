import Foundation

public enum AIError: Error, Equatable, CustomStringConvertible {
    case missingCredential
    case cancelled
    case timeout
    case unauthorized(String)
    case modelUnavailable(String)
    case quotaExhausted(String)
    case http(status: Int, message: String)
    case truncated(String)
    case malformedOutput(String)
    case transport(String)
    case unsupported(String)

    public var description: String {
        switch self {
        case .missingCredential: CoreText.text("还没有配置 API key")
        case .cancelled: CoreText.text("请求已取消")
        case .timeout: CoreText.text("请求超时")
        case let .unauthorized(message): CoreText.format("凭据无效：%@", message)
        case let .modelUnavailable(message): message
        case let .quotaExhausted(message): CoreText.format("额度或速率受限：%@", message)
        case let .http(status, message): CoreText.format("服务返回 %lld：%@", status, message)
        case let .truncated(reason): reason
        case let .malformedOutput(reason): CoreText.format("回复格式不符合约定：%@", reason)
        case let .transport(reason): CoreText.format("网络错误：%@", reason)
        case let .unsupported(reason): CoreText.format("当前服务或模型不支持：%@", reason)
        }
    }
}

public enum AIAPIStyle: String, Sendable, Codable {
    case chatCompletions
    case responses
}

/// 一家服务的接入参数。换地址、换模型都只改这里。
public struct AIProvider: Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var baseURL: URL
    public var apiStyle: AIAPIStyle
    public var chatCompletionsPath: String
    public var responsesPath: String
    public var defaultModel: String
    public var supportsStructuredOutput: Bool
    /// 只支持 `{"type": "json_object"}` 这类宽松 JSON 模式。
    public var supportsJSONMode: Bool
    /// 模型目录路径。为 nil 表示这家不提供目录接口。
    public var modelsPath: String?
    /// 目录所在的根地址。为空时用 baseURL。
    public var modelsBaseURL: URL?
    /// 服务没有目录接口时的内置清单，作者可以从中选或自己填。
    public var builtInModels: [String]
    /// OpenCode Go 要求每个会话带稳定标识，便于路由与缓存。
    public var requiresSessionHeader: Bool
    public var userAgent: String
    /// 这家服务接受的输出上限。超出的值会在发请求前被压回来，免得整条请求被拒。
    public var maxOutputTokensCeiling: Int

    public init(
        id: String,
        displayName: String,
        baseURL: URL,
        apiStyle: AIAPIStyle,
        chatCompletionsPath: String = "/v1/chat/completions",
        responsesPath: String = "/v1/responses",
        defaultModel: String,
        supportsStructuredOutput: Bool,
        supportsJSONMode: Bool = false,
        modelsPath: String? = "/v1/models",
        modelsBaseURL: URL? = nil,
        builtInModels: [String] = [],
        requiresSessionHeader: Bool = false,
        userAgent: String = "Causality/0.1 (macOS; +https://causality.local)",
        maxOutputTokensCeiling: Int = 16000
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.apiStyle = apiStyle
        self.chatCompletionsPath = chatCompletionsPath
        self.responsesPath = responsesPath
        self.defaultModel = defaultModel
        self.supportsStructuredOutput = supportsStructuredOutput
        self.supportsJSONMode = supportsJSONMode
        self.modelsPath = modelsPath
        self.modelsBaseURL = modelsBaseURL
        self.builtInModels = builtInModels
        self.requiresSessionHeader = requiresSessionHeader
        self.userAgent = userAgent
        self.maxOutputTokensCeiling = maxOutputTokensCeiling
    }

    /// 把想要的预算压到这家服务认得的范围。
    public func clampOutputTokens(_ wanted: Int) -> Int {
        min(max(wanted, 256), maxOutputTokensCeiling)
    }

    public var endpointURL: URL {
        switch apiStyle {
        case .chatCompletions:
            baseURL.appendingPathComponent(chatCompletionsPath)
        case .responses:
            baseURL.appendingPathComponent(responsesPath)
        }
    }

    public static let openAI = AIProvider(
        id: "openai",
        displayName: "OpenAI",
        baseURL: URL(string: "https://api.openai.com")!,
        apiStyle: .responses,
        defaultModel: "gpt-5.6-luna",
        supportsStructuredOutput: true,
        supportsJSONMode: true,
        modelsPath: "/v1/models",
        builtInModels: [
            "gpt-6-astra", "gpt-6-luna", "gpt-5.6-luna", "gpt-5.6", "gpt-4.1", "gpt-4o",
        ],
        maxOutputTokensCeiling: 32000
    )

    /// 产品侧给出的订阅专用入口。真实是否生效由联调确认，见 CLI 的 ai-probe。
    public static let openCodeGo = AIProvider(
        id: "opencode-go",
        displayName: "OpenCode Go",
        baseURL: URL(string: "https://opencode.ai/inference/go")!,
        apiStyle: .chatCompletions,
        chatCompletionsPath: "/openai/v1/chat/completions",
        responsesPath: "/openai/v1/responses",
        defaultModel: "glm-5.3",
        supportsStructuredOutput: false,
        supportsJSONMode: true,
        modelsPath: "/v1/models",
        modelsBaseURL: URL(string: "https://opencode.ai/inference"),
        builtInModels: [
            "glm-5.3", "glm-5.2", "kimi-k3", "kimi-k2.7-code", "minimax-m3",
            "qwen3.8-max", "qwen3.8-flash", "deepseek-v4.1-flash", "deepseek-v4-pro",
            "grok-4.7", "gpt-5.6-luna", "claude-haiku-5.5", "gemini-4-argon",
        ],
        requiresSessionHeader: true,
        maxOutputTokensCeiling: 32000
    )

    /// DeepSeek：OpenAI 兼容的 chat completions，支持宽松 JSON 模式。
    public static let deepSeek = AIProvider(
        id: "deepseek",
        displayName: "DeepSeek",
        baseURL: URL(string: "https://api.deepseek.com")!,
        apiStyle: .chatCompletions,
        chatCompletionsPath: "/chat/completions",
        defaultModel: "deepseek-flash",
        supportsStructuredOutput: false,
        supportsJSONMode: true,
        modelsPath: "/models",
        builtInModels: ["deepseek-flash", "deepseek-v4-pro"],
        maxOutputTokensCeiling: 8192
    )

    /// MiniMax 中国站：文本接口走 /v1/text/chatcompletion_v2，OpenAI 兼容的消息体。
    public static let miniMaxCN = AIProvider(
        id: "minimax-cn",
        displayName: "MiniMax（中国站）",
        baseURL: URL(string: "https://api.minimaxi.com")!,
        apiStyle: .chatCompletions,
        chatCompletionsPath: "/v1/text/chatcompletion_v2",
        defaultModel: "MiniMax-M2.7",
        supportsStructuredOutput: false,
        supportsJSONMode: false,
        modelsPath: "/v1/models",
        builtInModels: [
            "MiniMax-M3.1-Flash", "MiniMax-M3", "MiniMax-M2.7", "MiniMax-M2.7-highspeed",
            "MiniMax-M2.5", "MiniMax-M2.5-highspeed", "MiniMax-M2.1", "MiniMax-M2.1-highspeed",
            "MiniMax-M2", "M2-her",
        ],
        maxOutputTokensCeiling: 32000
    )

    /// 通义千问：DashScope 的 OpenAI 兼容入口。
    public static let qwen = AIProvider(
        id: "qwen",
        displayName: "通义千问",
        baseURL: URL(string: "https://dashscope.aliyuncs.com/compatible-mode")!,
        apiStyle: .chatCompletions,
        chatCompletionsPath: "/v1/chat/completions",
        defaultModel: "qwen-plus",
        supportsStructuredOutput: false,
        supportsJSONMode: true,
        modelsPath: "/v1/models",
        builtInModels: [
            "qwen3-max", "qwen3.5-plus", "qwen-plus", "qwen-turbo", "qwen-long",
        ],
        maxOutputTokensCeiling: 32000
    )

    /// 智谱 GLM：OpenAI 兼容入口。
    public static let glm = AIProvider(
        id: "glm",
        displayName: "智谱 GLM",
        baseURL: URL(string: "https://open.bigmodel.cn/api/paas/v4")!,
        apiStyle: .chatCompletions,
        chatCompletionsPath: "/chat/completions",
        defaultModel: "glm-4.6",
        supportsStructuredOutput: false,
        supportsJSONMode: true,
        modelsPath: "/models",
        builtInModels: ["glm-4.6", "glm-4.5", "glm-4-plus", "glm-4-flash"],
        maxOutputTokensCeiling: 16000
    )

    /// Google Gemini：官方 OpenAI 兼容入口。
    public static let gemini = AIProvider(
        id: "gemini",
        displayName: "Google Gemini",
        baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!,
        apiStyle: .chatCompletions,
        chatCompletionsPath: "/chat/completions",
        defaultModel: "gemini-2.5-flash",
        supportsStructuredOutput: false,
        supportsJSONMode: true,
        modelsPath: nil,
        builtInModels: ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"],
        maxOutputTokensCeiling: 32000
    )

    /// 豆包：火山方舟的 OpenAI 兼容入口；模型通常是 endpoint ID，目录接口不保证存在。
    public static let doubao = AIProvider(
        id: "doubao",
        displayName: "豆包（火山方舟）",
        baseURL: URL(string: "https://ark.cn-beijing.volces.com/api/v3")!,
        apiStyle: .chatCompletions,
        chatCompletionsPath: "/chat/completions",
        defaultModel: "doubao-seed-1-6-250615",
        supportsStructuredOutput: false,
        supportsJSONMode: true,
        modelsPath: nil,
        builtInModels: [
            "doubao-seed-1-6-250615", "doubao-seed-1-6-flash-250615",
            "doubao-1-5-pro-32k-250115", "doubao-1-5-lite-32k-250115",
        ],
        maxOutputTokensCeiling: 32000
    )

    /// ChatGPT 订阅登录：不走公开 API key，而是重用本机 Codex 的 OAuth 登录。
    public static let chatGPT = AIProvider(
        id: "chatgpt",
        displayName: "ChatGPT",
        baseURL: URL(string: "https://chatgpt.com/backend-api/codex")!,
        apiStyle: .responses,
        responsesPath: "/responses",
        defaultModel: "gpt-6-astra",
        supportsStructuredOutput: false,
        supportsJSONMode: false,
        modelsPath: nil,
        builtInModels: ["gpt-6-astra", "gpt-6-luna", "gpt-5.6-luna"],
        maxOutputTokensCeiling: 32000
    )

    /// OpenRouter：一个 key 接多家模型。
    public static let openRouter = AIProvider(
        id: "openrouter",
        displayName: "OpenRouter",
        baseURL: URL(string: "https://openrouter.ai/api")!,
        apiStyle: .chatCompletions,
        chatCompletionsPath: "/v1/chat/completions",
        defaultModel: "openai/gpt-4.1",
        supportsStructuredOutput: false,
        supportsJSONMode: true,
        modelsPath: "/v1/models",
        builtInModels: [
            "openai/gpt-5.6", "openai/gpt-4.1", "anthropic/claude-sonnet-4",
            "google/gemini-2.5-pro", "deepseek/deepseek-chat", "qwen/qwen3-max",
        ],
        maxOutputTokensCeiling: 32000
    )

    /// Kimi（Moonshot）：OpenAI 兼容入口。
    public static let kimi = AIProvider(
        id: "kimi",
        displayName: "Kimi",
        baseURL: URL(string: "https://api.moonshot.cn/v1")!,
        apiStyle: .chatCompletions,
        chatCompletionsPath: "/chat/completions",
        defaultModel: "kimi-k3",
        supportsStructuredOutput: false,
        supportsJSONMode: true,
        modelsPath: "/models",
        builtInModels: ["kimi-k3", "kimi-k2.7-code", "moonshot-v1-128k"],
        maxOutputTokensCeiling: 32000
    )

    public static let builtIn: [AIProvider] = [
        .chatGPT, .deepSeek, .openCodeGo, .openRouter, .kimi, .miniMaxCN, .qwen, .gemini, .doubao,
    ]
}

public struct AICredential: Sendable {
    public var apiKey: String
    public var sessionID: String
    /// ChatGPT 订阅登录需要的账户 ID；API key 服务为空。
    public var accountID: String?

    public init(apiKey: String, sessionID: String = UUID().uuidString, accountID: String? = nil) {
        self.apiKey = apiKey
        self.sessionID = sessionID
        self.accountID = accountID
    }

    public var isUsable: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// 一次对话轮次。发给模型时按 role 映射成 user / assistant。
public struct AIChatTurn: Sendable, Equatable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

public struct AIRequest: Sendable {
    public var provider: AIProvider
    public var model: String
    public var systemPrompt: String
    public var userMessage: String
    /// 之前的对话轮次。作者说「按刚才那个调子」时，模型得看得见「刚才」。
    public var history: [AIChatTurn]
    public var jsonSchema: String?
    public var maxOutputTokens: Int
    public var temperature: Double
    public var sessionID: String

    public init(
        provider: AIProvider,
        model: String,
        systemPrompt: String,
        userMessage: String,
        history: [AIChatTurn] = [],
        jsonSchema: String? = nil,
        maxOutputTokens: Int = 4000,
        temperature: Double = 0.4,
        sessionID: String = UUID().uuidString
    ) {
        self.provider = provider
        self.model = model
        self.systemPrompt = systemPrompt
        self.userMessage = userMessage
        self.history = history
        self.jsonSchema = jsonSchema
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.sessionID = sessionID
    }
}

public struct AICompletion: Sendable, Equatable {
    public var text: String
    public var model: String
    public var providerID: String
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var finishReason: String?
    /// 给作者看的一句话，说明这次回复为什么短了。为空表示正常收尾。
    public var note: String?

    public init(
        text: String,
        model: String,
        providerID: String,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        finishReason: String? = nil,
        note: String? = nil
    ) {
        self.text = text
        self.model = model
        self.providerID = providerID
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.finishReason = finishReason
        self.note = note
    }

    /// 模型撞到输出上限。这一种加预算还有救。
    public var isTruncated: Bool {
        finishReason == "length" || finishReason == "max_tokens" || finishReason == "incomplete"
    }

    /// 半路断线，正文是已经收到的部分。加预算没用，重发才有用。
    public var isInterrupted: Bool { finishReason == "interrupted" }
}

public enum AIStreamEvent: Sendable {
    /// 首字之前的本地状态由界面负责，这里只报文本增量。
    case textDelta(String)
    case completed(AICompletion)
}
