[English](mcp.md) · **简体中文**

# 连接 MCP 的细节与排查

主线步骤（装命令行、复制配置、让 AI 建故事板）见 `README.md` 第九节，细节在这里。

## 一、命令行从哪来

发布版 App 自带它，位置在 `Causality.app/Contents/Resources/cli/`：`causal` 加上它依赖的
`CausalityCore_CausalityCore.bundle`。设置（⌘,）› **MCP** 页里的「一键安装 MCP」（或菜单 **工具** 里的同名入口）会把这两个文件复制到当前用户主目录的 `.local/bin`——路径是运行时读主目录算的，不写死。

这一个按钮同时把它写进这台机器上检测到的 Codex / Hermes / Pi——调用各客户端自己的 `mcp add`，不手改配置——并按行显示自检结果（「已接入，N 个工具可用」／「还没接入」／「没连通：原因」），每行可单独「重新检查」。

没有命令行的桌面类客户端（Claude 桌面版、Cursor、Windsurf、Kiro、VS Code、OpenCode）走另一条路。判断装没装只看 `App` 包（`/Applications` 或 `~/Applications`）或命令行在不在；只有配置文件不算——有些工具会预建空的 `mcpServers` 骨架，拿它当证据会列出没装过的客户端。App 检测到就把它列出来，点「写入并检查」直接改那份 JSON（写前备份 `…bak-mcp-<时间>`，写后回读校验，非标准 JSON 不动手）。各客户端的位置与形状：

| 客户端 | 配置文件 | 键 | 条目形状 |
| --- | --- | --- | --- |
| Claude 桌面版 | `~/Library/Application Support/Claude/claude_desktop_config.json` | `mcpServers` | `command` + `args` |
| Cursor | `~/.cursor/mcp.json` | `mcpServers` | `command` + `args` |
| Windsurf | `~/.codeium/windsurf/mcp_config.json` | `mcpServers` | `command` + `args` |
| Kiro | `~/.kiro/settings/mcp.json` | `mcpServers` | `command` + `args` |
| VS Code | `~/Library/Application Support/Code/User/mcp.json` | `servers` | `type: stdio` + `command` + `args` |
| OpenCode | `~/.config/opencode/opencode.json` | `mcp` | `type: local` + `command: [路径, "mcp"]` |

表里的路径是这些客户端自己用的位置，App 只在检测到它之后才读写；两栏都没有的客户端（DSH 这类）才需要复制 `mcpServers` 片段手工粘。

只想用命令行、不装 App 的人，可以从 App 包里取 `Contents/Resources/cli/` 下的 `causal` 与同名 `.bundle`，用 `install.sh` 的方式装（会清隔离标记）。

## 二、配置落在哪

| 客户端 | 文件 | 键 |
| --- | --- | --- |
| Codex（ChatGPT 桌面端） | `~/.codex/config.toml` | `[mcp_servers.causal]` 的 `command` 与 `args` |
| Hermes | `~/.hermes/config.yaml` | `mcp_servers.causal` |
| Pi | `~/.pi/agent/mcp.json` | `mcpServers.causal` |

三处都指向同一个路径：`~/.local/bin/causal`，参数都是 `mcp`。指到别处（例如某个工程的 `.build/release/`）也能用，但那个目录会被重新编译或清理，连接随时会断。

## 三、工具清单

`causal mcp` 提供 15 个工具：

`open_project`、`save_project`、`project_info`、`project_export`、`list_chapters`、`list_cards`、`get_card`、`list_entities`、`apply_ops`、`import_markdown`、`history`、`undo`、`redo`、`validate`、`outline`。

`apply_ops` 认的操作名：`addChapter`、`updateChapter`、`deleteChapter`、`addCard`、`updateCard`、`deleteCard`、`moveCard`、`setEntry`、`connect`、`updateEdge`、`deleteEdge`、`arrangeCanvas`、`addCharacter`、`updateCharacter`、`deleteCharacter`、`addRelation`、`addPlace`、`updatePlace`、`addSetting`、`updateSetting`、`attachSetting`、`detachSetting`、`deleteSetting`、`updateHeader`。

引用卡片、章节、人物、地点、设定时写名字或 UUID 都行；名字重了会被拒绝并列出候选。

体检（N01–N21）不在 MCP 里：回 App 按 `⇧⌘A`，或命令行 `causal audit 工程.causal`。

## 四、验证连通

```bash
causal                                  # 打印用法，说明命令行能跑（没有 --version）
causal mcp-config                        # 打印给任意 MCP 客户端用的配置片段
hermes mcp test causal                   # Hermes 侧握手
codex mcp list                           # Codex 侧能看到 causal
pi mcp list                              # Pi 侧能看到 causal
```

再让客户端真的做一次调用，例如「打开 `/路径/示例.causal`，报一下章节数和卡片数」——它应该调用 `open_project` 与 `project_info`。

## 五、常见问题

| 症状 | 原因 | 处理 |
| --- | --- | --- |
| 启动即崩，提示 `unable to find bundle named CausalityCore_CausalityCore` | 只拷了 `causal`，没带 `CausalityCore_CausalityCore.bundle` | 用包里的 `install.sh` 重装，两个文件要在一起 |
| 第一次运行被系统杀掉（`Killed: 9`） | 下载件带隔离标记，而裸命令行工具没有可 staple 的公证票据 | 用 `install.sh` 装（它会清隔离标记）；手动拷的话补 `xattr -d com.apple.quarantine ~/.local/bin/causal` |
| 客户端里看不到 causal | 配置路径写错或没登记 | `list` 一遍；路径含空格要加引号 |
| 说写完了但 App 里没有 | 只 `apply_ops` 没 `save_project` | 让它补一次保存 |
| `401` | 用了 HTTP 传输却没带 token | stdio 不需要 token；`--transport http` 才需要 `CAUSAL_MCP_TOKEN`，只放环境变量或 `--token-file`，别写进 URL |
| 提示工程被别的程序改过 | App 或另一个客户端先保存了 | 按提示选「重新载入」或「另存为」 |
| 打开工程报版本高 | App 与 `causal` 版本不一致 | 两边更新到同一版本 |
