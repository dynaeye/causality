import AppKit
import Foundation
import Observation
import CausalityCore

/// 三个用途分开选模型：策划/大纲、写作、图片。
enum AIUsageRole: String, CaseIterable, Identifiable, Codable {
    case planning
    case writing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .planning: "策划 / 大纲"
        case .writing: "写作"
        }
    }

    var hint: String {
        switch self {
        case .planning: "讨论、整理大纲、分支梗概润色"
        case .writing: "改选中内容、在故事板缝隙插卡"
        }
    }
}

struct AIModelChoice: Codable, Equatable, Hashable {
    var providerID: String
    var model: String
}

/// 本机 Codex / ChatGPT 的 OAuth 缓存。只读取，不复制成第二份凭据。
private struct ChatGPTSession {
    var accessToken: String
    var accountID: String
    var expiresAt: Date?
}

enum ChatGPTAuthState {
    case missing
    case expired
    case connected
}

private struct StoredCustomProvider: Codable {
    var id: String
    var displayName: String
    var baseURL: String
    var models: [String]
    var defaultModel: String

    var provider: AIProvider? {
        guard let url = URL(string: baseURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return AIProvider(
            id: id,
            displayName: displayName,
            baseURL: url,
            apiStyle: .chatCompletions,
            chatCompletionsPath: "/chat/completions",
            responsesPath: "/chat/completions",
            defaultModel: defaultModel,
            supportsStructuredOutput: false,
            supportsJSONMode: true,
            modelsPath: "/models",
            builtInModels: models,
            maxOutputTokensCeiling: 32000
        )
    }
}

enum AICustomProviderError: LocalizedError {
    case invalidURL
    case noModels

    var errorDescription: String? {
        switch self {
        case .invalidURL: InterfaceLanguage.label("Base URL 要以 http:// 或 https:// 开头，并包含域名。")
        case .noModels: InterfaceLanguage.label("至少填一个模型 ID。")
        }
    }
}

/// AI 服务的全局设置：服务、模型、密钥。属于整个 App，不属于某个窗口。
@MainActor
@Observable
final class AISettingsStore {
    static let shared = AISettingsStore()

    private(set) var provider: AIProvider
    /// 当前正在编辑 API key 的服务里的模型。三个用途的模型在 roleChoices 里。
    private(set) var model: String = ""
    private(set) var modelOptions: [String] = []
    /// 每个服务在本次运行里是否已经自动尝试过目录；切回 AI 页签时不再重复拉。
    private(set) var modelRefreshAttempted: Set<String> = []
    private(set) var fetching = false
    private(set) var error: String?
    private(set) var notice: String?
    private(set) var hasCredential = false
    private(set) var savedAt: Date?
    private(set) var customProviders: [AIProvider] = []
    private(set) var roleChoices: [AIUsageRole: AIModelChoice] = [:]
    @ObservationIgnored private var chatGPTLoginProcess: Process?

    /// OpenCode Go 要求会话里带稳定标识。
    let sessionID = UUID().uuidString

    @ObservationIgnored private let client = AIClient()
    private static let providerKey = "causal.aiProvider"
    private static let rolesKey = "causal.aiRoles"
    private static let customProvidersKey = "causal.aiCustomProviders"

    private static func modelKey(_ providerID: String) -> String {
        "causal.aiModel.\(providerID)"
    }

    private init() {
        let loadedCustom = Self.loadCustomProviders()
        customProviders = loadedCustom
        let defaults = UserDefaults.standard
        let storedID = defaults.string(forKey: Self.providerKey)
        provider = (AIProvider.builtIn + loadedCustom).first { $0.id == storedID } ?? .openCodeGo
        refreshCredentialStatus()
        model = Self.initialModel(for: provider, hasCredential: hasCredential)

        roleChoices = Self.loadRoleChoices()

        // 已经删掉的自定义服务不能再留在角色绑定里。
        let known = Set(providers.map(\.id))
        roleChoices = roleChoices.filter { known.contains($0.value.providerID) }
        let fallbackModel = model.isEmpty ? provider.defaultModel : model
        if roleChoices[.planning] == nil, !fallbackModel.isEmpty {
            roleChoices[.planning] = AIModelChoice(providerID: provider.id, model: fallbackModel)
        }
        if roleChoices[.writing] == nil, let planning = roleChoices[.planning] {
            roleChoices[.writing] = planning
        }
        pruneUnconfiguredRoles()
        saveRoleChoices()
    }

    var providers: [AIProvider] {
        AIProvider.builtIn + customProviders
    }

    /// 模型分工只列已经配置过凭据的服务。
    var configuredProviders: [AIProvider] {
        providers.filter { hasCredential(for: $0.id) }
    }

    func pruneUnconfiguredRoles() {
        let configured = Set(configuredProviders.map(\.id))
        let next = roleChoices.filter { configured.contains($0.value.providerID) }
        guard next != roleChoices else { return }
        roleChoices = next
        saveRoleChoices()
    }

    func provider(id: String) -> AIProvider? {
        providers.first { $0.id == id }
    }

    private static func initialModel(for provider: AIProvider, hasCredential: Bool) -> String {
        guard hasCredential else { return "" }
        return UserDefaults.standard.string(forKey: modelKey(provider.id)) ?? ""
    }

    // MARK: - 角色

    func choice(for role: AIUsageRole) -> AIModelChoice? {
        roleChoices[role]
    }

    func provider(for role: AIUsageRole) -> AIProvider? {
        guard let choice = roleChoices[role] else { return nil }
        return provider(id: choice.providerID)
    }

    func model(for role: AIUsageRole) -> String {
        roleChoices[role]?.model ?? ""
    }

    func setRoleProvider(_ role: AIUsageRole, providerID: String) {
        guard let next = provider(id: providerID) else { return }
        let current = roleChoices[role]
        let model: String
        if let current, current.providerID == next.id, !current.model.isEmpty {
            model = current.model
        } else if !next.defaultModel.isEmpty {
            model = next.defaultModel
        } else {
            model = next.builtInModels.first ?? ""
        }
        roleChoices[role] = AIModelChoice(providerID: next.id, model: model)
        saveRoleChoices()
    }

    func setRoleModel(_ role: AIUsageRole, model: String) {
        guard let current = roleChoices[role] else { return }
        roleChoices[role] = AIModelChoice(providerID: current.providerID, model: model)
        saveRoleChoices()
    }

    /// 角色下拉里可选的模型：内置清单 + 当前选中的模型；当前服务拉回来的目录也并进来。
    func availableModels(for role: AIUsageRole) -> [String] {
        guard let current = roleChoices[role],
              let provider = provider(id: current.providerID) else { return [] }
        var models = provider.builtInModels
        if provider.id == self.provider.id {
            models += modelOptions
        }
        if !current.model.isEmpty, !models.contains(current.model) {
            models.insert(current.model, at: 0)
        }
        if !provider.defaultModel.isEmpty, !models.contains(provider.defaultModel) {
            models.insert(provider.defaultModel, at: 0)
        }
        var seen: Set<String> = []
        return models.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func loadRoleChoices() -> [AIUsageRole: AIModelChoice] {
        guard let data = UserDefaults.standard.data(forKey: rolesKey),
              let raw = try? JSONDecoder().decode([String: AIModelChoice].self, from: data) else {
            return [:]
        }
        var result: [AIUsageRole: AIModelChoice] = [:]
        for (key, value) in raw {
            if let role = AIUsageRole(rawValue: key) {
                result[role] = value
            }
        }
        return result
    }

    private func saveRoleChoices() {
        let raw = Dictionary(uniqueKeysWithValues: roleChoices.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: Self.rolesKey)
        }
    }

    // MARK: - 服务与模型

    func selectProvider(_ newProvider: AIProvider) {
        guard newProvider.id != provider.id else { return }
        if !model.isEmpty {
            UserDefaults.standard.set(model, forKey: Self.modelKey(provider.id))
        }
        provider = newProvider
        UserDefaults.standard.set(newProvider.id, forKey: Self.providerKey)
        modelOptions = []
        modelRefreshAttempted.remove(newProvider.id)
        error = nil
        notice = nil
        refreshCredentialStatus()
        model = Self.initialModel(for: newProvider, hasCredential: hasCredential)
    }

    func selectModel(_ newModel: String) {
        model = newModel
        UserDefaults.standard.set(newModel, forKey: Self.modelKey(provider.id))
    }

    /// 只在本次运行里首次打开该服务的 AI 页签时自动拉目录。
    func ensureModelsLoaded() {
        guard hasCredential,
              modelOptions.isEmpty,
              !modelRefreshAttempted.contains(provider.id),
              !fetching else { return }
        refreshModels()
    }

    /// 从服务目录读模型；目录不可用时退回内置清单，作者仍可手填。
    func refreshModels() {
        guard let credential = loadCredential() else {
            error = InterfaceLanguage.label("先填 API key")
            return
        }
        error = nil
        notice = nil
        fetching = true
        modelRefreshAttempted.insert(provider.id)
        let currentProvider = provider
        Task {
            defer { fetching = false }
            do {
                let models = try await client.listModels(provider: currentProvider, credential: credential)
                if models.isEmpty {
                    useBuiltInModels(for: currentProvider, reason: InterfaceLanguage.label("目录里没有模型"))
                } else {
                    // 先把默认模型选好，再换 options；避免 Picker 先以“无选中”状态闪一下。
                    adoptDefaultModel(from: models)
                    modelOptions = models
                }
            } catch {
                let reason = (error as? AIError)?.description ?? error.localizedDescription
                useBuiltInModels(for: currentProvider, reason: reason)
            }
        }
    }

    private func useBuiltInModels(for provider: AIProvider, reason: String) {
        guard !provider.builtInModels.isEmpty else {
            modelOptions = []
            error = reason
            return
        }
        notice = String(format: InterfaceLanguage.label("服务没有返回目录（%@），先列内置清单，也可以手动改。"), reason)
        adoptDefaultModel(from: provider.builtInModels)
        modelOptions = provider.builtInModels
    }

    private func adoptDefaultModel(from models: [String]) {
        guard model.isEmpty || !models.contains(model) else { return }
        if !provider.defaultModel.isEmpty, models.contains(provider.defaultModel) {
            selectModel(provider.defaultModel)
        } else {
            model = ""
            notice = InterfaceLanguage.label("目录里没有默认模型，请自己选一个。部分模型有地区限制，请求失败时换一个即可。")
        }
    }

    // MARK: - 自定义服务

    func addCustomProvider(name: String, baseURL: String, apiKey: String, modelsText: String) throws {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            throw AICustomProviderError.invalidURL
        }
        let models = modelsText
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen: Set<String> = []
        let uniqueModels = models.filter { seen.insert($0).inserted }
        guard let defaultModel = uniqueModels.first else {
            throw AICustomProviderError.noModels
        }
        let id = "custom-\(UUID().uuidString)"
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "自定义服务"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = StoredCustomProvider(
            id: id,
            displayName: displayName,
            baseURL: trimmedURL,
            models: uniqueModels,
            defaultModel: defaultModel
        )
        guard let custom = stored.provider else { throw AICustomProviderError.invalidURL }
        customProviders.append(custom)
        saveCustomProviders()
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            try AICredentialStore.save(trimmedKey, for: id)
        }
        selectProvider(custom)
        savedAt = trimmedKey.isEmpty ? savedAt : Date()
        pruneUnconfiguredRoles()
    }

    func removeCustomProvider(id: String) {
        guard customProviders.contains(where: { $0.id == id }) else { return }
        customProviders.removeAll { $0.id == id }
        saveCustomProviders()
        AICredentialStore.delete(providerID: id)
        roleChoices = roleChoices.filter { $0.value.providerID != id }
        pruneUnconfiguredRoles()
        saveRoleChoices()
        if provider.id == id, let fallback = AIProvider.builtIn.first {
            provider = fallback
            model = ""
            modelOptions = []
            refreshCredentialStatus()
        }
    }

    private static func loadCustomProviders() -> [AIProvider] {
        guard let data = UserDefaults.standard.data(forKey: customProvidersKey),
              let raw = try? JSONDecoder().decode([StoredCustomProvider].self, from: data) else {
            return []
        }
        return raw.compactMap(\.provider)
    }

    private func saveCustomProviders() {
        let raw = customProviders.map { provider in
            StoredCustomProvider(
                id: provider.id,
                displayName: provider.displayName,
                baseURL: provider.baseURL.absoluteString,
                models: provider.builtInModels,
                defaultModel: provider.defaultModel
            )
        }
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: Self.customProvidersKey)
        }
    }

    // MARK: - ChatGPT 登录

    static var chatGPTAuthURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
    }

    private static func loadChatGPTSession(allowExpired: Bool = false) -> ChatGPTSession? {
        guard let data = try? Data(contentsOf: chatGPTAuthURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["auth_mode"] as? String == "chatgpt",
              let tokens = object["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty,
              let account = tokens["account_id"] as? String, !account.isEmpty else {
            return nil
        }
        let session = ChatGPTSession(
            accessToken: token,
            accountID: account,
            expiresAt: Self.accessTokenExpiry(token)
        )
        if !allowExpired,
           let expiresAt = session.expiresAt,
           expiresAt <= Date().addingTimeInterval(60) {
            return nil
        }
        return session
    }

    var chatGPTAuthState: ChatGPTAuthState {
        guard let session = Self.loadChatGPTSession(allowExpired: true) else { return .missing }
        if let expiresAt = session.expiresAt, expiresAt <= Date().addingTimeInterval(60) {
            return .expired
        }
        return .connected
    }

    var isChatGPTConnected: Bool { chatGPTAuthState == .connected }

    var chatGPTStatusLabel: String {
        switch chatGPTAuthState {
        case .missing: "未登录"
        case .expired: "登录过期"
        case .connected: "已登录"
        }
    }

    private static func accessTokenExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let seconds = object["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// 打开 ChatGPT 网页登录。已有 Codex 登录时直接复用，不重复弹一次。
    @discardableResult
    func openChatGPTWebLogin() -> String {
        if Self.loadChatGPTSession() != nil {
            return finishChatGPTLogin()
        }
        guard let codex = Self.codexExecutableURL() else {
            NSWorkspace.shared.open(URL(string: "https://chatgpt.com/auth/login")!)
            return InterfaceLanguage.label("已打开 ChatGPT 网页登录；完成后回到这里点「重新检测」。")
        }
        let process = Process()
        process.executableURL = codex
        process.arguments = ["login"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            chatGPTLoginProcess = process
            return InterfaceLanguage.label("已打开网页登录；在浏览器完成验证后回到这里点「重新检测」。")
        } catch {
            let message = String(format: InterfaceLanguage.label("打不开 Codex 登录：%@"), error.localizedDescription)
            self.error = message
            return message
        }
    }

    /// 重新读取本机 Codex 的 ChatGPT 登录；成功后把策划档切到 ChatGPT。
    @discardableResult
    func connectChatGPT() -> String {
        switch chatGPTAuthState {
        case .missing:
            let message = InterfaceLanguage.label("尚未检测到 ChatGPT 网页登录。先点「网页登录」，在浏览器完成验证后再回来。")
            error = message
            return message
        case .expired:
            let message = InterfaceLanguage.label("ChatGPT 登录已过期。请点「网页登录」重新验证，验证完成后再回来。")
            error = message
            return message
        case .connected:
            return finishChatGPTLogin()
        }
    }

    private func finishChatGPTLogin() -> String {
        selectProvider(.chatGPT)
        setRoleProvider(.planning, providerID: AIProvider.chatGPT.id)
        if roleChoices[.writing] == nil || !hasCredential(for: roleChoices[.writing]!.providerID) {
            setRoleProvider(.writing, providerID: AIProvider.chatGPT.id)
        }
        pruneUnconfiguredRoles()
        savedAt = Date()
        error = nil
        hasCredential = true
        return InterfaceLanguage.label("已连接本机 ChatGPT 登录，策划/大纲已切到 ChatGPT。")
    }

    private static func codexExecutableURL() -> URL? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            NSHomeDirectory() + "/.local/bin/codex",
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }

    // MARK: - 密钥

    func loadCredential() -> AICredential? {
        loadCredential(for: provider.id)
    }

    func loadCredential(for providerID: String) -> AICredential? {
        if providerID == AIProvider.chatGPT.id {
            guard let session = Self.loadChatGPTSession() else { return nil }
            return AICredential(
                apiKey: session.accessToken,
                sessionID: sessionID,
                accountID: session.accountID
            )
        }
        guard let key = AICredentialStore.load(providerID: providerID), !key.isEmpty else { return nil }
        return AICredential(apiKey: key, sessionID: sessionID)
    }

    func hasCredential(for providerID: String) -> Bool {
        if providerID == AIProvider.chatGPT.id {
            return Self.loadChatGPTSession() != nil
        }
        return AICredentialStore.load(providerID: providerID) != nil
    }

    func saveCredential(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = InterfaceLanguage.label("密钥是空的")
            return
        }
        do {
            try AICredentialStore.save(trimmed, for: provider.id)
            error = nil
            savedAt = Date()
            refreshCredentialStatus()
            pruneUnconfiguredRoles()
            refreshModels()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func clearCredential() {
        AICredentialStore.delete(providerID: provider.id)
        modelOptions = []
        modelRefreshAttempted.remove(provider.id)
        model = ""
        savedAt = nil
        refreshCredentialStatus()
        pruneUnconfiguredRoles()
    }

    func refreshCredentialStatus() {
        hasCredential = hasCredential(for: provider.id)
    }
}


extension AIProvider {
    /// 服务名里只有少数是中文品牌；跟随界面语言显示，CLI 不受影响。
    var localizedDisplayName: String { InterfaceLanguage.label(displayName) }
}
