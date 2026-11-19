import AppKit
import CausalityCore
import SwiftUI

/// 设置里的「MCP」页：一个按钮把命令行装好、写进已装的 AI 客户端，并逐个自检是否连通。
/// 目标是用户不用开终端、不用改配置文件、也不用粘 JSON。
struct CLISettingsView: View {
    @Environment(\.theme) private var theme
    @State private var installedPath: String?
    @State private var message: String?
    @State private var isError = false
    @State private var clientState: [String: ClientMCPState] = [:]
    @State private var configState: [String: ConfigClientState] = [:]
    @State private var busyClientID: String?
    @State private var isInstallingAll = false

    private var installedURL: URL {
        CLITool.defaultInstallDirectory.appendingPathComponent(CLITool.binaryName)
    }

    private var bundled: URL? { CLITool.bundledDirectory() }

    private var detectedClients: [CLIClient] { CLIClient.allCases.filter(\.isInstalled) }

    /// 靠配置文件接入、已经装在这台机器上的客户端
    private var detectedConfigClients: [ConfigClient] { ConfigClient.allCases.filter { $0.isInstalled() } }

    /// 一个线索都没有的：只在兜底区把通用配置给它
    private var missingClients: [ConfigClient] { ConfigClient.allCases.filter { !$0.isInstalled() } }

    private var cliURL: URL? {
        guard let installedPath else { return nil }
        return URL(fileURLWithPath: installedPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Button {
                        installEverything()
                    } label: {
                        HStack(spacing: 6) {
                            if isInstallingAll { ProgressView().controlSize(.small) }
                            Text(isInstallingAll ? "正在安装…" : "一键安装 MCP")
                        }
                    }
                    .disabled(isInstallingAll || bundled == nil)

                    Text("装好命令行，并把它写进这台机器上已经安装的 AI 客户端；写完逐个自检能不能连上。")
                        .font(theme.fontMin)
                        .foregroundStyle(theme.textSecondary)

                    if bundled == nil {
                        Text("这个版本没有自带命令行。官网 DMG 里的 App 自带它；开发和源码构建的版本不含。")
                            .font(theme.fontMin)
                            .foregroundStyle(theme.warning)
                    }
                }

                Section("Codex / Hermes / Pi") {
                    if detectedClients.isEmpty {
                        Text("没检测到这三个。它们有命令行，装好后回到这一页点「一键安装 MCP」，App 会让它们自己写入。")
                            .font(theme.fontMin)
                            .foregroundStyle(theme.textSecondary)
                    } else {
                        ForEach(detectedClients) { client in
                            clientRow(client)
                        }
                    }
                }

                Section("桌面类客户端（App 直接改它的配置文件）") {
                    if detectedConfigClients.isEmpty {
                        Text("没检测到 Claude 桌面版、Cursor、Windsurf、Kiro、VS Code、OpenCode。装了其中之一再回到这一页，它就会出现在这里。")
                            .font(theme.fontMin)
                            .foregroundStyle(theme.textSecondary)
                    } else {
                        ForEach(detectedConfigClients) { client in
                            configClientRow(client)
                        }
                    }
                }

                Section("还需要的才手动处理") {
                    Text(manualHint)
                        .font(theme.fontMin)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    configText
                    HStack {
                        Button("复制这段配置") { copyConfig() }
                            .disabled(installedPath == nil)
                        Button("打开命令行所在文件夹") {
                            NSWorkspace.shared.activateFileViewerSelecting([installedURL])
                        }
                        .disabled(!FileManager.default.fileExists(atPath: installedURL.path))
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(theme.background)
        }
        .background(theme.background)
        .task { await refreshAll() }
        .alert(message ?? "", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        }
    }

    private func clientRow(_ client: CLIClient) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon(for: client))
                .foregroundStyle(color(for: client))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(client.displayName).font(theme.fontBody)
                Text(statusText(for: client))
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(busyClientID == client.id ? "检查中…" : "重新检查") {
                check(client)
            }
            .disabled(busyClientID != nil || isInstallingAll || cliURL == nil)
        }
    }

    private var configText: some View {
        Text(CLITool.mcpConfig(executable: installedURL))
            .font(.system(size: 11, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func icon(for client: CLIClient) -> String {
        switch clientState[client.id] {
        case .configured: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "circle.dashed"
        }
    }

    private func color(for client: CLIClient) -> Color {
        switch clientState[client.id] {
        case .configured: theme.accent
        case .failed: theme.warning
        default: theme.textTertiary
        }
    }

    private func statusText(for client: CLIClient) -> String {
        guard cliURL != nil else { return "还没安装命令行" }
        return switch clientState[client.id] {
        case let .configured(tools): "已接入，\(tools) 个工具可用"
        case let .failed(reason): "没连通：\(reason)"
        case .notConfigured: "还没接入"
        case .none: "还没检查"
        }
    }

    /// 一个按钮：装命令行 → 逐个客户端写入 → 逐个自检。
    private func installEverything() {
        guard let bundled else { return }
        isInstallingAll = true
        Task {
            do {
                let installed = try CLITool.install(from: bundled, into: CLITool.defaultInstallDirectory)
                installedPath = installed.path
                clientState = [:]
                for client in detectedClients {
                    busyClientID = client.id
                    _ = try? await CLITool.register(client, cli: installed)
                    clientState[client.id] = await client.check(cli: installed)
                }
                for client in detectedConfigClients {
                    busyClientID = client.id
                    _ = try? client.write(cli: installed)
                    configState[client.id] = client.status(cli: installed)
                }
                busyClientID = nil
                isInstallingAll = false
                let connected = detectedClients.filter { clientState[$0.id]?.isOK == true }.count
                    + detectedConfigClients.filter { configState[$0.id]?.isOK == true }.count
                message = connected > 0
                    ? "已装到 \(installed.path)，\(connected) 个客户端接入并连通。重启对应客户端或让它重新加载 MCP 即可使用。"
                    : "已装到 \(installed.path)，但还没有客户端连通。看下面每行的原因。"
            } catch {
                isInstallingAll = false
                busyClientID = nil
                message = error.localizedDescription
            }
        }
    }

    private func check(_ client: CLIClient) {
        guard let cliURL else { return }
        busyClientID = client.id
        Task {
            clientState[client.id] = await client.check(cli: cliURL)
            busyClientID = nil
        }
    }

    private func refreshAll() async {
        installedPath = FileManager.default.isExecutableFile(atPath: installedURL.path)
            ? installedURL.path
            : nil
        guard let cliURL else { return }
        for client in detectedClients {
            clientState[client.id] = await client.check(cli: cliURL)
        }
        for client in detectedConfigClients {
            configState[client.id] = client.status(cli: cliURL)
        }
    }


    // MARK: - 桌面类客户端（改配置文件）

    private func configClientRow(_ client: ConfigClient) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon(for: client))
                .foregroundStyle(color(for: client))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(client.displayName).font(theme.fontBody)
                Text(statusText(for: client))
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(client.configURL().path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Button(busyClientID == client.id ? "写入中…" : "写入并检查") {
                    writeConfig(client)
                }
                .disabled(busyClientID != nil || isInstallingAll || cliURL == nil)
                Button("在访达中显示") { reveal(client) }
                    .buttonStyle(.link)
            }
        }
    }

    private func icon(for client: ConfigClient) -> String {
        switch configState[client.id] {
        case .configured: "checkmark.circle.fill"
        case .notWritable, .stalePath: "exclamationmark.triangle.fill"
        default: "circle.dashed"
        }
    }

    private func color(for client: ConfigClient) -> Color {
        switch configState[client.id] {
        case .configured: theme.accent
        case .notWritable, .stalePath: theme.warning
        default: theme.textTertiary
        }
    }

    private func statusText(for client: ConfigClient) -> String {
        guard cliURL != nil else { return "还没安装命令行" }
        return switch configState[client.id] {
        case .configured: "已接入，配置文件里指向现在这份命令行"
        case let .stalePath(path): path.isEmpty
            ? "配过，但没写命令行路径"
            : "配过，但指向的是 \(path)（换过位置？点「写入并检查」）"
        case let .notWritable(reason): reason
        case .notConfigured: "还没接入"
        case .none: "还没检查"
        }
    }

    private var manualHint: String {
        let missing = missingClients.map(\.displayName)
        let list = missing.isEmpty
            ? "DSH 这类没有固定配置位置的客户端"
            : "\(missing.joined(separator: "、"))，以及 DSH 这类没有固定配置位置的客户端"
        return "上面两栏之外的客户端（\(list)）才需要手工：在它自己的设置里找 MCP / Model Context Protocol 一项，把下面这段粘进去，保存，重启它，然后回到这一页看它有没有出现在列表里。用「复制这段配置」按钮复制，别手动选中文字——那样会带出 \\n、&#x20; 之类的转义。"
    }

    private func writeConfig(_ client: ConfigClient) {
        guard let cliURL else { return }
        busyClientID = client.id
        Task {
            do {
                let backup = try client.write(cli: cliURL)
                configState[client.id] = client.status(cli: cliURL)
                let where_ = client.configURL().path
                if let backup {
                    message = "已写入 \(client.displayName)：\(where_)\n原文件备份为 \(backup.lastPathComponent)。重启该客户端后生效。"
                } else {
                    message = "已写入 \(client.displayName)：\(where_)\n重启该客户端后生效。"
                }
            } catch {
                configState[client.id] = client.status(cli: cliURL)
                message = error.localizedDescription
            }
            busyClientID = nil
        }
    }

    private func reveal(_ client: ConfigClient) {
        let url = client.configURL()
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let folder = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
    }

    private func copyConfig() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(CLITool.mcpConfig(executable: installedURL), forType: .string)
        message = "配置已复制（纯文本，不带转义）。"
    }
}
