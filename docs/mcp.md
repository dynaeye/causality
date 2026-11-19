**English** · [简体中文](mcp.zh-Hans.md)

# MCP connection details and troubleshooting

The main steps — installing the command line, copying the config, having an AI build a storyboard — are in section 9 of `README.md`. This page holds the details.

## 1. Where the command line comes from

The release app ships it under `Causality.app/Contents/Resources/cli/`: `causal` together with the `CausalityCore_CausalityCore.bundle` it depends on. "Install MCP in one click" on the Settings (⌘,) › **MCP** page (or the same entry in the **Tools** menu) copies both into `.local/bin` under the current user's home directory — the path is computed from the home directory at runtime, never hard-coded.

That one button also registers it with the Codex / Hermes / Pi detected on this machine — by calling each client's own `mcp add` rather than editing config by hand — and shows a per-line self-check result ("Connected, N tools available" / "Not connected yet" / "Failed: reason"), each line recheckable on its own.

Desktop clients without a command line (Claude Desktop, Cursor, Windsurf, Kiro, VS Code, OpenCode) take another route. "Installed" is judged by the app bundle (`/Applications` or `~/Applications`) or the command existing; a config file alone does not count — some tools pre-create an empty `mcpServers` skeleton, and treating that as evidence would list clients you never installed. Once detected, the app lists the client, and "Write and check" edits that JSON directly (backing up to `…bak-mcp-<time>` first, reading back to verify, and leaving non-standard JSON untouched). Where each client keeps its file, and in what shape:

| Client | Config file | Key | Entry shape |
| --- | --- | --- | --- |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` | `mcpServers` | `command` + `args` |
| Cursor | `~/.cursor/mcp.json` | `mcpServers` | `command` + `args` |
| Windsurf | `~/.codeium/windsurf/mcp_config.json` | `mcpServers` | `command` + `args` |
| Kiro | `~/.kiro/settings/mcp.json` | `mcpServers` | `command` + `args` |
| VS Code | `~/Library/Application Support/Code/User/mcp.json` | `servers` | `type: stdio` + `command` + `args` |
| OpenCode | `~/.config/opencode/opencode.json` | `mcp` | `type: local` + `command: [path, "mcp"]` |

The paths above are the ones those clients use themselves; the app only reads and writes after detecting one. Only clients in neither list (DSH and the like) need the `mcpServers` snippet copied and pasted by hand.

If you want the command line alone, without the app, take `causal` and the same-named `.bundle` from `Contents/Resources/cli/` inside the app package and install them the way `install.sh` does (which clears the quarantine flag).

## 2. Where the config lands

| Client | File | Key |
| --- | --- | --- |
| Codex (ChatGPT desktop) | `~/.codex/config.toml` | `command` and `args` under `[mcp_servers.causal]` |
| Hermes | `~/.hermes/config.yaml` | `mcp_servers.causal` |
| Pi | `~/.pi/agent/mcp.json` | `mcpServers.causal` |

All three point at one path, `~/.local/bin/causal`, with the argument `mcp`. Pointing somewhere else (a project's `.build/release/`, say) works, but that directory gets rebuilt or cleaned and the connection drops with it.

## 3. Tool list

`causal mcp` provides 15 tools:

`open_project`, `save_project`, `project_info`, `project_export`, `list_chapters`, `list_cards`, `get_card`, `list_entities`, `apply_ops`, `import_markdown`, `history`, `undo`, `redo`, `validate`, `outline`.

Operation names `apply_ops` accepts: `addChapter`, `updateChapter`, `deleteChapter`, `addCard`, `updateCard`, `deleteCard`, `moveCard`, `setEntry`, `connect`, `updateEdge`, `deleteEdge`, `arrangeCanvas`, `addCharacter`, `updateCharacter`, `deleteCharacter`, `addRelation`, `addPlace`, `updatePlace`, `addSetting`, `updateSetting`, `attachSetting`, `detachSetting`, `deleteSetting`, `updateHeader`.

Cards, chapters, characters, places, and settings can be referenced by name or UUID; a duplicate name is rejected with the candidates listed.

The checkup (N01–N21) is not in MCP: return to the app and press `⇧⌘A`, or run `causal audit project.causal`.

## 4. Verifying the connection

```bash
causal                                  # prints usage, showing the CLI runs (there is no --version)
causal mcp-config                        # prints a config snippet for any MCP client
hermes mcp test causal                   # handshake on the Hermes side
codex mcp list                           # Codex sees causal
pi mcp list                              # Pi sees causal
```

Then have the client make a real call, for example "open `/path/sample.causal` and report the chapter and card counts" — it should call `open_project` and `project_info`.

## 5. Common problems

| Symptom | Cause | Fix |
| --- | --- | --- |
| Crashes at launch with `unable to find bundle named CausalityCore_CausalityCore` | Only `causal` was copied, without `CausalityCore_CausalityCore.bundle` | Reinstall with the bundled `install.sh`; the two files travel together |
| Killed by the system on first run (`Killed: 9`) | The download carries a quarantine flag, and a bare command-line tool has no notarisation ticket to staple | Install with `install.sh` (it clears the flag); for a manual copy, run `xattr -d com.apple.quarantine ~/.local/bin/causal` |
| The client does not see causal | Wrong config path, or nothing registered | Run `list`; quote paths containing spaces |
| Says it finished, but the app shows nothing | `apply_ops` without `save_project` | Have it save once |
| `401` | HTTP transport without a token | stdio needs no token; `--transport http` needs `CAUSAL_MCP_TOKEN`, kept in the environment or `--token-file`, never in the URL |
| Warns that the project was changed by another program | The app or another client saved first | Choose "Reload" or "Save a copy" as prompted |
| Opening a project reports a version that is too new | App and `causal` versions differ | Update both to the same version |
