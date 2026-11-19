import Foundation

/// `causal mcp-config`
///
/// 输出一段任何 MCP 客户端都能用的配置：`mcpServers` 里一条 `command` + `args`。
/// 不绑定具体客户端——Claude、OpenCode、DSH、Kiro、Codex、Hermes、Pi 都是这个形状，
/// 只是各自把这段放在不同的配置文件里。
func runMCPConfig(_ args: Arguments) -> Int32 {
    let executable: String
    if let explicit = args.values["command"], !explicit.isEmpty {
        executable = explicit
    } else {
        executable = CommandLine.arguments.first.map { path -> String in
            let url = URL(fileURLWithPath: path)
            return url.standardizedFileURL.path
        } ?? "causal"
    }

    // 路径里的反斜杠与引号按 JSON 规则转义，避免生成坏 JSON。
    let escaped = executable
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")

    let json = """
    {
      "mcpServers": {
        "causality": {
          "command": "\(escaped)",
          "args": ["mcp"]
        }
      }
    }

    """
    FileHandle.standardOutput.write(Data(json.utf8))
    return 0
}
