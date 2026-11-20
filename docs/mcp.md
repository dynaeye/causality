**English** · [简体中文](mcp.zh-Hans.md)

# MCP connection details and troubleshooting

The main steps — installing the command line, writing the config, having an AI build a storyboard — are in section 9 of `README.md`. This page holds the details.

## 1. Where the command line comes from

The release app ships it under `Causality.app/Contents/Resources/cli/`: `causal` together with the `CausalityCore_CausalityCore.bundle` it depends on. The **Install MCP** button (一键安装 MCP) on the Settings (⌘,) › **MCP** page copies both into `.local/bin` under the current user's home directory; so does **Tools › Install Command-Line Tool** (工具 › 安装命令行工具), which only installs the files. The path is worked out from the home directory at runtime.

That one button also registers the CLI with the Codex / Hermes / Pi found on this machine, by calling each client's own `mcp add` rather than editing config files by hand, and then shows a per-line verdict — **Connected, N tools available** (已接入，N 个工具可用), **Not connected yet** (还没接入), or **Not connected: reason** (没连通：原因) — each line recheckable on its own.

Desktop clients with no command line (Claude Desktop, Cursor, Windsurf, Kiro, VS Code, OpenCode) take another route. Whether one is installed is judged by the app bundle in `/Applications` or `~/Applications`, or by the command existing; a config file alone does not count, since some tools pre-create an empty `mcpServers` skeleton and treating that as evidence would list clients you never installed. Once detected, the app lists the client and **Write and Check** (写入并检查) edits that JSON directly, backing it up to `…bak-mcp-<time>` first, reading it back to verify, and leaving non-standard JSON untouched. Where each client keeps its file, and in what shape:

| Client | Config file | Key | Entry shape |
| --- | --- | --- | --- |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` | `mcpServers` | `command` + `args` |
| Cursor | `~/.cursor/mcp.json` | `mcpServers` | `command` + `args` |
| Windsurf | `~/.codeium/windsurf/mcp_config.json` | `mcpServers` | `command` + `args` |
| Kiro | `~/.kiro/settings/mcp.json` | `mcpServers` | `command` + `args` |
| VS Code | `~/Library/Application Support/Code/User/mcp.json` | `servers` | `type: stdio` + `command` + `args` |
| OpenCode | `~/.config/opencode/opencode.json` | `mcp` | `type: local` + `command: [path, "mcp"]` |

Those paths belong to the clients themselves; the app only reads and writes after detecting one. Clients in neither list (DSH and the like) take the manual route: copy the `mcpServers` snippet and paste it in.

For the command line alone, without the app, take `causal` and the `CausalityCore_CausalityCore.bundle` beside it from `Contents/Resources/cli/` inside the app package and install them the way `install.sh` does, which also clears the quarantine flag.

## 2. Where the config lands

| Client | File | Key |
| --- | --- | --- |
| Codex (ChatGPT desktop) | `~/.codex/config.toml` | `command` and `args` under `[mcp_servers.causal]` |
| Hermes | `~/.hermes/config.yaml` | `mcp_servers.causal` |
| Pi | `~/.pi/agent/mcp.json` | `mcpServers.causal` |

All three point at one path, `~/.local/bin/causal`, with the argument `mcp`. Pointing elsewhere works — at a project's `.build/release/`, say — but that directory gets rebuilt or cleaned and the connection drops with it.

## 3. Tool list

`causal mcp` provides 15 tools:

`open_project`, `save_project`, `project_info`, `project_export`, `list_chapters`, `list_cards`, `get_card`, `list_entities`, `apply_ops`, `import_markdown`, `history`, `undo`, `redo`, `validate`, `outline`.

Operations `apply_ops` accepts: `addChapter`, `updateChapter`, `deleteChapter`, `addCard`, `updateCard`, `deleteCard`, `moveCard`, `setEntry`, `connect`, `updateEdge`, `deleteEdge`, `arrangeCanvas`, `addCharacter`, `updateCharacter`, `deleteCharacter`, `addRelation`, `addPlace`, `updatePlace`, `addSetting`, `updateSetting`, `attachSetting`, `detachSetting`, `deleteSetting`, `updateHeader`.

Cards, chapters, characters, places, and story facts can be referenced by name or by UUID; a duplicate name is rejected with the candidates listed.

Story Check (N01–N21) lives in the app: press `⇧⌘A` there, or run `causal audit project.causal`.

## 4. Verifying the connection

```bash
causal                                  # prints usage, which shows the CLI runs (there is no --version)
causal mcp-config                        # prints a config snippet for any MCP client
hermes mcp test causal                   # handshake on the Hermes side
codex mcp list                           # Codex sees causal
pi mcp list                              # Pi sees causal
```

Then have the client make a real call, something like "open `/path/sample.causal` and report the chapter and card counts"; it should call `open_project` and `project_info`.

## 5. Common problems

| Symptom | Cause | Fix |
| --- | --- | --- |
| Crashes at launch with `unable to find bundle named CausalityCore_CausalityCore` | Only `causal` was copied, without `CausalityCore_CausalityCore.bundle` | Reinstall with the bundled `install.sh`; the two files travel together |
| Killed by the system on first run (`Killed: 9`) | The download carries a quarantine flag, and a bare command-line tool has no notarisation ticket to staple | Install with `install.sh`, which clears the flag; for a manual copy, run `xattr -d com.apple.quarantine ~/.local/bin/causal` |
| The client does not see causal | Wrong config path, or nothing registered | Run `list`; quote any path containing spaces |
| Says it finished, but the app shows nothing | `apply_ops` ran without `save_project` | Have it save once |
| `401` | HTTP transport without a token | stdio needs no token; `--transport http` needs `CAUSAL_MCP_TOKEN` in the environment or `--token-file`, never in the URL |
| Warns that the project was changed by another program | The app or another client saved first | Choose **Save As…**, **Overwrite on Disk**, or **Reload from Disk** as prompted |
| Opening a project reports a version that is too new | App and `causal` versions differ | Update both to the same version |
