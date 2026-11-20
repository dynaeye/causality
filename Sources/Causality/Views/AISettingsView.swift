import CausalityCore
import SwiftUI

struct AISettingsView: View {
    @Environment(\.theme) private var theme
    @State private var keyDraft: String = ""
    @State private var showingCustomProvider = false
    @State private var customName = ""
    @State private var customURL = ""
    @State private var customKey = ""
    @State private var customModels = ""
    @State private var customError: String?
    @State private var chatGPTMessage: String?
    @State private var expandedProviderID: String?

    private var store: AISettingsStore { .shared }

    var body: some View {
        VStack(spacing: 0) {
            connectHeader
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 2)

            Form {
                Section("设置提供商") {
                    providerSection
                }

                Section("模型分工") {
                    roleSection
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(theme.background)
        }
        .background(theme.background)
        .task {
            store.pruneUnconfiguredRoles()
            store.ensureModelsLoaded()
        }
        .onAppear {
            store.pruneUnconfiguredRoles()
        }
        .onChange(of: store.provider.id) { _, _ in
            store.ensureModelsLoaded()
        }
        .sheet(isPresented: $showingCustomProvider) {
            customProviderSheet
        }
    }

    // MARK: - 连接

    private var connectHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("连接你的 AI 提供商")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("请使用你现有已订阅中的大模型")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 提供商

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(store.providers) { provider in
                providerCard(provider)
            }

            Button {
                customError = nil
                showingCustomProvider = true
            } label: {
                Label("添加自定义提供商…", systemImage: "plus.circle")
                    .font(theme.fontMin)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    private func providerCard(_ provider: AIProvider) -> some View {
        let selected = store.provider.id == provider.id
        let expanded = expandedProviderID == provider.id
        let connected = store.hasCredential(for: provider.id)
        let statusText: String = if provider.id == AIProvider.chatGPT.id {
            store.chatGPTStatusLabel
        } else {
            connected ? InterfaceLanguage.label("已设置 API 密钥") : InterfaceLanguage.label("未设置")
        }
        let statusColor: Color = connected
            ? .green
            : (provider.id == AIProvider.chatGPT.id && store.chatGPTAuthState == .expired ? theme.warning : theme.textTertiary)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if expanded {
                    expandedProviderID = nil
                } else {
                    store.selectProvider(provider)
                    expandedProviderID = provider.id
                    keyDraft = ""
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: providerIcon(provider.id))
                        .font(.system(size: 15))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(verbatim: provider.localizedDisplayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 6)

                    Text(LocalizedStringKey(statusText))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.12), in: Capsule())

                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    selected ? theme.accentSoft : theme.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? theme.accent.opacity(0.5) : theme.border, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                keyEditor(for: provider)
                    .padding(.horizontal, 10)
                    .padding(.top, 7)
                    .padding(.bottom, 2)
            }
        }
    }

    private func keyEditor(for provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if provider.id == AIProvider.chatGPT.id {
                HStack(spacing: 8) {
                    Text(LocalizedStringKey(store.isChatGPTConnected ? "已通过网页验证登录" : "使用网页验证登录 ChatGPT"))
                        .font(theme.fontMin)
                        .foregroundStyle(theme.textTertiary)
                    Spacer()
                    Button(LocalizedStringKey(store.isChatGPTConnected ? "重新检测" : "网页登录")) {
                        chatGPTMessage = store.isChatGPTConnected
                            ? store.connectChatGPT()
                            : store.openChatGPTWebLogin()
                    }
                    .controlSize(.small)
                }
                if let chatGPTMessage {
                    Text(chatGPTMessage)
                        .font(.caption)
                        .foregroundStyle(store.isChatGPTConnected ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.warning))
                        .lineLimit(3)
                }
            } else if store.hasCredential(for: provider.id) {
                HStack(spacing: 8) {
                    filledKeyField
                    Button("清除") {
                        store.clearCredential()
                        keyDraft = ""
                    }
                }
            } else {
                HStack(spacing: 8) {
                    SecureField("输入 API key", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveKey() }
                    Button("存进钥匙串") { saveKey() }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func providerIcon(_ id: String) -> String {
        switch id {
        case AIProvider.chatGPT.id: "sparkles"
        case AIProvider.deepSeek.id: "water.waves"
        case AIProvider.openCodeGo.id: "chevron.left.forwardslash.chevron.right"
        case AIProvider.openRouter.id: "arrow.triangle.branch"
        case AIProvider.kimi.id: "moon.stars"
        case AIProvider.miniMaxCN.id: "square.grid.2x2"
        case AIProvider.qwen.id: "cloud"
        case AIProvider.gemini.id: "diamond"
        case AIProvider.doubao.id: "bolt"
        default: "slider.horizontal.3"
        }
    }

    /// 已保存时按普通密码框的样子显示一串星号。
    private var filledKeyField: some View {
        TextField("", text: .constant(String(repeating: "*", count: 32)))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(true)
    }

    private func saveKey() {
        guard !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.saveCredential(keyDraft)
        keyDraft = ""
    }

    // MARK: - 模型分工

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(AIUsageRole.allCases) { role in
                roleRow(role)
            }
        }
    }

    private func roleRow(_ role: AIUsageRole) -> some View {
        let choice = store.choice(for: role)
        let provider = choice.flatMap { store.provider(id: $0.providerID) }
        let models = store.availableModels(for: role)
        let configuredProviders = store.configuredProviders
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: roleIcon(role))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(role.displayName))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(LocalizedStringKey(role.hint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if configuredProviders.isEmpty {
                Text("先在上方设置提供商，才能给这一档选模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Text("提供商")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .leading)
                    Menu {
                        ForEach(configuredProviders) { item in
                            Button {
                                store.setRoleProvider(role, providerID: item.id)
                            } label: {
                                if choice?.providerID == item.id {
                                    Label(item.localizedDisplayName, systemImage: "checkmark")
                                } else {
                                    Text(verbatim: item.localizedDisplayName)
                                }
                            }
                        }
                    } label: {
                        roleMenuLabel(provider?.localizedDisplayName ?? InterfaceLanguage.label("选择提供商"), active: provider != nil)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: 155, alignment: .leading)

                    Text("模型")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                    Menu {
                        ForEach(models, id: \.self) { model in
                            Button {
                                store.setRoleModel(role, model: model)
                            } label: {
                                if choice?.model == model {
                                    Label(model, systemImage: "checkmark")
                                } else {
                                    Text(model)
                                }
                            }
                        }
                    } label: {
                        roleMenuLabel(choice?.model.isEmpty == false ? choice!.model : InterfaceLanguage.label("选择模型"), active: choice != nil)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: 190, alignment: .leading)
                    .disabled(choice == nil || models.isEmpty)
                }
            }

            if let provider, !store.hasCredential(for: provider.id) {
                Text("这个提供商还没有配置 API key。")
                    .font(.caption)
                    .foregroundStyle(theme.warning)
            }
        }
        .padding(10)
        .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.border, lineWidth: 1)
        }
    }

    private func roleMenuLabel(_ text: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
        }
        .font(.system(size: 12))
        .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(theme.border, lineWidth: 1)
        }
    }

    private func roleIcon(_ role: AIUsageRole) -> String {
        switch role {
        case .planning: "map"
        case .writing: "square.and.pencil"
        }
    }

    // MARK: - 自定义服务

    private var customProviderSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("添加自定义提供商")
                .font(.headline)

            Form {
                TextField("名称", text: $customName)
                TextField("Base URL（如 https://api.example.com/v1）", text: $customURL)
                SecureField("API key（也可以稍后填）", text: $customKey)
                TextField("模型 ID，用逗号分隔", text: $customModels)
            }
            .formStyle(.grouped)

            if let customError {
                Text(customError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("取消") {
                    showingCustomProvider = false
                }
                Spacer()
                Button("添加") {
                    do {
                        try store.addCustomProvider(
                            name: customName,
                            baseURL: customURL,
                            apiKey: customKey,
                            modelsText: customModels
                        )
                        showingCustomProvider = false
                        customName = ""
                        customURL = ""
                        customKey = ""
                        customModels = ""
                        customError = nil
                    } catch {
                        customError = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(customURL.trimmingCharacters(in: .whitespaces).isEmpty
                          || customModels.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
