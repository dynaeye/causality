import AppKit
import Darwin
import Foundation

/// 让用户不用开终端就能用上命令行（MCP 服务器）。
///
/// 发布版把 `causal` 与它的资源包放在 `Causality.app/Contents/Resources/cli/`，
/// 这里负责把它们复制到 `~/.local/bin`，并生成任何 MCP 客户端都能用的配置片段。
enum CLITool {
    static let binaryName = "causal"
    static let resourceBundleName = "CausalityCore_CausalityCore.bundle"
    private static let bundledResourceDirectory = "cli"

    enum Failure: LocalizedError {
        case missingInApp
        case copyFailed(String)
        case clientNotInstalled(String)
        case registerFailed(String)
        case configNotJSON(String)
        case writeNotVerified(String)

        var errorDescription: String? {
            switch self {
            case .missingInApp:
                "这个 App 里没有自带命令行（开发版常见）。请用官网 DMG 安装的版本。"
            case let .copyFailed(reason):
                "复制失败：\(reason)"
            case let .clientNotInstalled(name):
                "没有找到 \(name) 的命令行，无法自动写入。可以用下面的配置手工粘贴。"
            case let .configNotJSON(name):
                "\(name) 的配置不是标准 JSON，没有改动它。点「打开配置文件」自己看一眼。"
            case let .writeNotVerified(name):
                "写进 \(name) 后回读对不上，请点「打开配置文件」确认。"
            case let .registerFailed(reason):
                "写入失败：\(reason)"
            }
        }
    }

    /// App 包内自带命令行的目录。
    static func bundledDirectory(in bundle: Bundle = .main) -> URL? {
        guard let resources = bundle.resourceURL else { return nil }
        let directory = resources.appendingPathComponent(bundledResourceDirectory, isDirectory: true)
        let binary = directory.appendingPathComponent(binaryName)
        return FileManager.default.isExecutableFile(atPath: binary.path) ? directory : nil
    }

    static var defaultInstallDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin", isDirectory: true)
    }

    /// 幂等安装：重复点就覆盖成当前 App 自带的版本。
    @discardableResult
    static func install(from source: URL, into destination: URL) throws -> URL {
        let manager = FileManager.default
        let sourceBinary = source.appendingPathComponent(binaryName)
        guard manager.isExecutableFile(atPath: sourceBinary.path) else {
            throw Failure.missingInApp
        }
        do {
            try manager.createDirectory(
                at: destination,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            let target = destination.appendingPathComponent(binaryName)
            try? manager.removeItem(at: target)
            try manager.copyItem(at: sourceBinary, to: target)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)

            let sourceBundle = source.appendingPathComponent(resourceBundleName)
            if manager.fileExists(atPath: sourceBundle.path) {
                let targetBundle = destination.appendingPathComponent(resourceBundleName)
                try? manager.removeItem(at: targetBundle)
                try manager.copyItem(at: sourceBundle, to: targetBundle)
            }
            removeQuarantine(target)
            return target
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.copyFailed(error.localizedDescription)
        }
    }

    /// 通用 MCP 配置：`mcpServers` 里一条 command + args，任何支持的客户端都认这个形状。
    static func mcpConfig(executable: URL) -> String {
        let escaped = executable.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {
          "mcpServers": {
            "causality": {
              "command": "\(escaped)",
              "args": ["mcp"]
            }
          }
        }

        """
    }

    /// 从 App 包里拷出来的文件本来没有隔离标记；顺手清一次，避免任何情况下被 Gatekeeper 拦。
    private static func removeQuarantine(_ url: URL) {
        removexattr(url.path, "com.apple.quarantine", 0)
    }
}

/// 菜单动作：装完后用系统弹窗告诉用户结果，不用开终端。
@MainActor
enum CLIToolActions {
    static func installCLI() {
        guard let source = CLITool.bundledDirectory() else {
            present(
                title: "这个版本没有自带命令行",
                message: "官网 DMG 里的 App 自带命令行。开发和源码构建的版本不含它。"
            )
            return
        }
        do {
            let installed = try CLITool.install(from: source, into: CLITool.defaultInstallDirectory)
            present(
                title: "命令行工具已装好",
                message: """
                位置：\(installed.path)

                接下来在任意支持 MCP 的 AI 客户端里，用菜单「工具 › 复制 MCP 配置」拿到一段 JSON，贴进它的 MCP 配置即可。
                """
            )
        } catch {
            present(title: "没装成", message: error.localizedDescription)
        }
    }

    static func copyMCPConfig() {
        let executable = CLITool.defaultInstallDirectory.appendingPathComponent(CLITool.binaryName)
        let config = CLITool.mcpConfig(executable: executable)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(config, forType: .string)
        present(
            title: "MCP 配置已复制",
            message: """
            已复制到剪贴板：

            \(config)
            没有装命令行的话，先点「工具 › 安装命令行工具」。
            """
        )
    }

    private static func present(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}


/// 本机装了的常见 MCP 客户端。只有检测到可执行文件才显示，不猜配置路径。
enum CLIClient: String, CaseIterable, Identifiable, Sendable {
    case codex
    case hermes
    case pi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "GPT（Codex）"
        case .hermes: "Hermes"
        case .pi: "Pi"
        }
    }

    var executableCandidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .codex:
            return [
                "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                "\(home)/.local/bin/codex",
                "/usr/local/bin/codex",
                "/opt/homebrew/bin/codex",
            ]
        case .hermes:
            return ["\(home)/.local/bin/hermes", "/opt/homebrew/bin/hermes", "/usr/local/bin/hermes"]
        case .pi:
            return ["\(home)/.local/bin/pi", "/opt/homebrew/bin/pi", "/usr/local/bin/pi"]
        }
    }

    var executable: URL? {
        executableCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    var isInstalled: Bool { executable != nil }

    /// 用客户端自己的 CLI 注册，写完即生效；不需要用户碰配置文件。
    func arguments(cli: URL) -> [String] {
        switch self {
        case .codex, .pi:
            ["mcp", "add", "causality", "--", cli.path, "mcp"]
        case .hermes:
            ["mcp", "add", "causality", "--command", cli.path, "--args", "mcp"]
        }
    }

    /// Hermes 注册时会问「Enable all 15 tools?」，回车取默认值。
    var needsConfirmation: Bool { self == .hermes }
}

extension CLITool {
    /// 调用客户端自己的 CLI 写配置。失败时把它的原始输出带回来，便于排查。
    static func register(_ client: CLIClient, cli: URL) async throws -> String {
        guard let executable = client.executable else {
            throw Failure.clientNotInstalled(client.displayName)
        }
        let arguments = client.arguments(cli: cli)
        let confirmation = client.needsConfirmation

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let input = Pipe()
            let output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = output
            do {
                try process.run()
            } catch {
                throw Failure.registerFailed(error.localizedDescription)
            }
            if confirmation {
                input.fileHandleForWriting.write(Data("Y\n".utf8))
            }
            try? input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw Failure.registerFailed(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "退出码 \(process.terminationStatus)"
                        : text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}


/// 某个客户端的 MCP 配置与连通状态。
enum ClientMCPState: Equatable, Sendable {
    case notConfigured
    case configured(tools: Int)
    case failed(String)

    var isOK: Bool { if case .configured = self { return true }; return false }
}

extension CLIClient {
    /// 查这个客户端有没有配 causal、以及配的那条命令能不能起来。
    /// 判断依据：客户端自己的命令能查到条目 + `causal mcp` 真能完成一次握手。
    func check(cli: URL) async -> ClientMCPState {
        guard let executable else { return .failed("没有找到它的命令行") }

        // 1) 客户端自己怎么看待这条配置
        let (ok, output) = await CLIClient.run(
            executable: executable,
            arguments: checkArguments,
            confirmation: nil
        )
        guard ok else {
            // 「没配过」不是失败，要分开显示
            let lowered = output.lowercased()
            if lowered.contains("not found") || lowered.contains("no mcp servers") {
                return .notConfigured
            }
            return .failed(output.isEmpty ? "查询失败" : output)
        }
        let configured: Bool
        switch self {
        case .codex:
            configured = output.contains("command")
        case .hermes:
            // `mcp test` 会真的连一次，能过说明通了
            configured = output.contains("✓") || output.lowercased().contains("ok") || output.contains("success")
        case .pi:
            configured = output.contains("causality")
        }
        guard configured else { return .notConfigured }

        // 2) 那条命令能不能真的握手（与客户端无关的通用检查）
        do {
            let tools = try await CLITool.probeTools(cli: cli)
            return .configured(tools: tools)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private var checkArguments: [String] {
        switch self {
        case .codex: ["mcp", "get", "causality"]
        case .hermes: ["mcp", "test", "causality"]
        case .pi: ["mcp", "list"]
        }
    }

    /// 跑客户端命令，返回（是否成功，输出）。
    static func run(
        executable: URL,
        arguments: [String],
        confirmation: String?
    ) async -> (Bool, String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let input = Pipe()
                let output = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = output
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: (false, error.localizedDescription))
                    return
                }
                if let confirmation {
                    input.fileHandleForWriting.write(Data(confirmation.utf8))
                }
                try? input.fileHandleForWriting.close()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(
                    returning: (
                        process.terminationStatus == 0,
                        text.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
            }
        }
    }
}

extension CLITool {
    /// 起一次 `causal mcp`，完成 initialize + tools/list，返回工具数。
    /// 写完全部请求后关掉 stdin，服务端读到 EOF 自行退出，不需要超时逻辑。
    static func probeTools(cli: URL) async throws -> Int {
        let initialize = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"causality","version":"1"}}}"#
        let list = #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#
        let script = initialize + "\n" + list + "\n"

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = cli
                process.arguments = ["mcp"]
                let input = Pipe()
                let output = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: Failure.registerFailed(error.localizedDescription))
                    return
                }
                input.fileHandleForWriting.write(Data(script.utf8))
                try? input.fileHandleForWriting.close()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(data: data, encoding: .utf8) ?? ""
                for line in text.split(separator: "\n") {
                    guard let parsed = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                          let result = parsed["result"] as? [String: Any],
                          let tools = result["tools"] as? [Any] else { continue }
                    continuation.resume(returning: tools.count)
                    return
                }
                continuation.resume(throwing: Failure.registerFailed("MCP 没有回应握手"))
            }
        }
    }
}


/// 靠一份 JSON 配置接入的客户端（桌面 App 类）。检测到就由 App 直接写入，
/// 用户不用打开文件、不用粘 JSON；写入前留备份。
enum ConfigClient: String, CaseIterable, Identifiable, Sendable {
    case claudeDesktop
    case cursor
    case windsurf
    case kiro
    case vsCode
    case openCode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeDesktop: "Claude（桌面版）"
        case .cursor: "Cursor"
        case .windsurf: "Windsurf"
        case .kiro: "Kiro"
        case .vsCode: "VS Code"
        case .openCode: "OpenCode"
        }
    }

    /// 算不算「装过」：只看 App 包或命令行在不在。
    /// **不能拿配置文件当证据**——很多工具会预建一个空的 mcpServers 骨架，
    /// 把它当安装会把没装的客户端列出来（Kiro/Claude 就踩过这个坑）。
    /// `home` 可注入，测试用临时目录跑真实写入，不碰用户自己的配置。
    func isInstalled(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let fm = FileManager.default
        if appBundleCandidates.contains(where: fm.fileExists(atPath:)) { return true }
        return commandLineCandidates(home: home).contains { fm.isExecutableFile(atPath: $0) }
    }

    /// App 可能装在 `/Applications`，也可能只装在当前用户自己的 `~/Applications`。
    private var appBundleCandidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let name: String? = switch self {
        case .claudeDesktop: "Claude.app"
        case .cursor: "Cursor.app"
        case .windsurf: "Windsurf.app"
        case .kiro: "Kiro.app"
        case .vsCode: "Visual Studio Code.app"
        case .openCode: nil
        }
        guard let name else { return [String]() }
        return ["/Applications/\(name)", "\(home)/Applications/\(name)"]
    }

    private func commandLineCandidates(home: URL) -> [String] {
        let home = home.path
        return switch self {
        case .openCode: ["\(home)/.local/bin/opencode", "/opt/homebrew/bin/opencode", "/usr/local/bin/opencode"]
        default: [String]()
        }
    }

    /// 各客户端自己认的那份配置文件。
    func configURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let home = home.path
        let path: String = switch self {
        case .claudeDesktop: "\(home)/Library/Application Support/Claude/claude_desktop_config.json"
        case .cursor: "\(home)/.cursor/mcp.json"
        case .windsurf: "\(home)/.codeium/windsurf/mcp_config.json"
        case .kiro: "\(home)/.kiro/settings/mcp.json"
        case .vsCode: "\(home)/Library/Application Support/Code/User/mcp.json"
        case .openCode: "\(home)/.config/opencode/opencode.json"
        }
        return URL(fileURLWithPath: path)
    }

    /// 它把服务放在哪个键下面：多数用 mcpServers，VS Code 用 servers，OpenCode 用 mcp。
    var rootKey: String {
        switch self {
        case .vsCode: "servers"
        case .openCode: "mcp"
        default: "mcpServers"
        }
    }

    /// 一条服务条目，按各客户端要求的形状生成。
    func entry(cli: URL) -> [String: Any] {
        switch self {
        case .vsCode:
            ["type": "stdio", "command": cli.path, "args": ["mcp"]]
        case .openCode:
            ["type": "local", "command": [cli.path, "mcp"], "enabled": true]
        default:
            ["command": cli.path, "args": ["mcp"]]
        }
    }

    var serverName: String { "causality" }

    /// 读它现在的配置，看有没有我们这条、路径对不对。
    func status(cli: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ConfigClientState {
        let url = configURL(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return .notConfigured }
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .notWritable("这份配置不是标准 JSON，我没敢改；可以用下面的「打开配置文件」自己看一眼")
        }
        guard let servers = root[rootKey] as? [String: Any],
              let ours = servers[serverName] as? [String: Any] else {
            return .notConfigured
        }
        let command = (ours["command"] as? String)
            ?? (ours["command"] as? [String])?.first
            ?? ""
        if command == cli.path { return .configured }
        return .stalePath(command)
    }

    /// 把一条服务并进已有配置：别人的条目原样保留，我们这条覆盖成当前路径。
    static func merged(_ root: [String: Any], client: ConfigClient, cli: URL) -> [String: Any] {
        var root = root
        var servers = root[client.rootKey] as? [String: Any] ?? [:]
        servers[client.serverName] = client.entry(cli: cli)
        root[client.rootKey] = servers
        return root
    }

    /// 写入我们这条，保留文件里其他内容；写前备份，写后回读校验。
    @discardableResult
    func write(cli: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL? {
        let fm = FileManager.default
        let url = configURL(home: home)
        var root: [String: Any] = [:]
        var backup: URL?
        if fm.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            if !data.isEmpty {
                guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw CLITool.Failure.configNotJSON(displayName)
                }
                root = parsed
            }
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let destination = url.deletingLastPathComponent()
                .appendingPathComponent(url.lastPathComponent + ".bak-mcp-\(stamp)")
            try? fm.copyItem(at: url, to: destination)
            backup = destination
        }
        root = Self.merged(root, client: self, cli: cli)

        try fm.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let output = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try output.write(to: url, options: .atomic)

        // 回读确认真的写进去了
        guard status(cli: cli, home: home) == .configured else {
            throw CLITool.Failure.writeNotVerified(displayName)
        }
        return backup
    }
}

/// 配置文件类客户端的接入状态。
enum ConfigClientState: Equatable, Sendable {
    case notConfigured
    case configured
    /// 配过，但指向的不是现在这份命令行（常见于换过安装位置）
    case stalePath(String)
    case notWritable(String)

    var isOK: Bool { self == .configured }
}
