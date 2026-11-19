**English** · [简体中文](cli.zh-Hans.md)

# Command-line interface (causal)

A stable entry point for scripts, CI, and the MCP server. Every read and write goes through the same model-layer code the app runs, so results here match what you see there.

```bash
cd Packages/CausalityCore
swift build -c release          # the binary lands in .build/release/causal
```

Put it on PATH by symlink or by copying it:

```bash
ln -sf "$PWD/.build/release/causal" /usr/local/bin/causal
```

## Commands

| Command | Purpose |
| --- | --- |
| `causal import <storyboard.md> [output.causal] [--title title] [--lang en\|ja\|zh-Hant]` | Turn a text storyboard into a project package; `--lang` picks the phrasing language (English/Japanese table headers, three-part card labels, CLI messages) |
| `causal info <package.causal>` | Print chapters, cards, causality, idea cards |
| `causal validate <package.causal>` | Run model-layer validation; exit 1 when something is wrong |
| `causal outline <package.causal>` | Print the derived outline (Markdown) |
| `causal apply <package.causal> --ops ops.json` | Edit a project from a script and write the package back |
| `causal undo <package.causal> [--steps N]` | Step back through history snapshots |
| `causal redo <package.causal> [--steps N]` | Reapply what was just stepped back |
| `causal export <package.causal> [--out file]` | Export the full project.json, after the contract check |
| `causal contract <export.json>` | Check required fields against schemaVersion |
| `causal audit <package.causal> [--all]` | Run the N01–N21 Story Check; exit 1 on errors |
| `causal branch <package.causal> [--to ending] [--mode segments\|per-path]` | Branch synopsis |
| `causal reach <package.causal> --from <card>` | Which endings a card can reach, and how many steps away |
| `causal play <package.causal> [--choices 1,1] [--out reading-copy.md]` | Single-path play through, plus a reading copy |
| `causal thread <package.causal>` | List threads and the points on each one |
| `causal mcp [--package package] [--transport stdio\|http]` | Start the MCP server; stdio by default, HTTP needs a token |

Everything except `export` and `mcp` takes `--json`, which puts a single JSON object on stdout.

Exit codes: `0` success, `1` failure (file unreadable, package unopenable, validation failed), `2` usage error.

## Language (`--lang`)

CLI messages, reports, the three-part card labels, and MCP server text all come from one string table in `CausalityCore`, and `--lang` selects the language.

- Values: `zh-Hans`, `en`, `ja`, `zh-Hant`. Regional spellings work too (`zh-TW` / `zh-HK` / `zh-MO` → `zh-Hant`, `en-US` → `en`, `ja-JP` → `ja`).
- Position: before or after the subcommand; `--lang en` and `--lang=en` are the same thing.
- Precedence: an explicit `--lang` wins, then storyboard header inference, then the language prefix of `LANG`, then the `zh-Hans` default.
- Headers: storyboard import always recognises the Chinese headers, plus the set for the current language (`Beat and Timing` / `ビートとタイミング` / `節點與時機`). A document with Traditional Chinese headers needs `--lang zh-Hant` for its headers to be recognised; the same argument decides whether the three-part card labels read `Sees / Does / Leaves` or `見る / する / 残る`.
- MCP: with `causal mcp --lang en`, `tools/list` descriptions, `tools/call` error text, and the HTTP transport's handshake and auth messages all come back in English.

```bash
causal --lang ja validate project.causal      # before the subcommand
causal mcp --lang en                          # after the subcommand
causal mcp --transport http --lang ja         # mixed with other arguments
```

## What import understands

The importer recognises four header sets — Chinese, English, Japanese, and Traditional Chinese (`节点与时机`, `Beat and Timing`, `ビートとタイミング`, `節點與時機`) — and writes the three-part card labels in the header's language: `Sees / Does / Leaves`, `見る / する / 残る`, `眼前 / 動手 / 留下`. When a header is ambiguous, name the language with `--lang en|ja|zh-Hant`; the CLI's own messages, reports, and card labels follow the same string table (see "Language" above).

Detection is automatic: a document containing a `| 节点与时机 |` table goes through storyboard import, anything else through plain Markdown import. `--format storyboard|prose` forces either one.

**Plain Markdown**: `#` is the project name, `##` is a chapter, `###`/`####` are scenes, and remaining paragraphs go into scene text; a chapter with no `###` collapses into a single scene. Tables under `## 人物` / `## 地点` / `## 设定` (characters / places / settings), or `- **Name**: description` lines, create the matching entities and attach them by name to the scenes they appear in.

```markdown
# Letters in the Rain

**A one-line logline.**

## Act One · The Letter

### Scene One · The Envelope

Lin Yuan receives a letter on a rainy night.

## Characters

| Name | Description |
|---|---|
| Lin Yuan | The recipient. |
```

**Storyboard table**:

```markdown
# 《Town》 Opening Storyboard   ← H1, used as the project name when --title is absent

**A paragraph of logline.**      ← project logline (carried in AI context)

## Act One · Subtitle           ← a chapter

| 节点与时机 | What the player sees | What the player does | What remains, and how it leads to the next scene |
|---|---|---|---|
| S01 Arrival, afternoon | … | … | … |
```

- The first row is the header; the first column ("number short name, timing") splits into the card title and a note.
- The other three columns go into the scene text, prefixed `眼前：` / `动手：` / `留下：` (sees / does / leaves).
- Cards are joined causally in row order, and each edge takes the first sentence of the "what remains" column.
- A table whose header is something else (a four-way table, say) becomes idea cards and stays off the storyboard.
- `- **Subtitle**: text` inside a chapter also becomes an idea card.
- Characters, places, and story facts come only from in-document `## 人物` / `## 地点` / `## 设定` sections; with no such section, nothing is created, and no sample library is preloaded.
- JSON from prose import carries `"mode": "prose"` plus one `notes` entry (chapters and scenes).

## JSON structure

Shared by `import` and `info`:

```json
{
  "ok": true,
  "command": "import",
  "package": "/abs/path/sample.causal",
  "title": "Sample · Opening Storyboard",
  "logline": "A generic sample project: from the protagonist moving into a new place to the first solo trip.…",
  "revision": 0,
  "metadataBytes": 26995,
  "counts": { "chapters": 3, "cards": 9, "ideas": 8, "edges": 8,
              "characters": 4, "places": 7, "settings": 4 },
  "chapters": [ { "id": "…", "title": "Act One · Settling In", "cards": 2 } ],
  "warnings": []
}
```

`info` adds `cards` and `edges`:

```json
"cards": [{
  "id": "…", "title": "S01 Arrival", "kind": "event", "status": "draft",
  "chapter": "Act One · Settling In",
  "summary": "The rain has just stopped; the protagonist arrives with luggage to stay with the landlord.…",
  "body": "Sees: …\n\nDoes: …\n\nLeaves: …",
  "characters": ["Landlord"], "places": ["Courtyard"], "settings": [],
  "outgoing": 1, "incoming": 0
}],
"edges": [{ "id": "…", "from": "S01 Arrival", "to": "S02 Seeing the Craft",
            "kind": "plain", "label": "Gets the key to his own room", "condition": "" }]
```

A failure carries two fields:

```json
{ "ok": false, "error": "cannot open /path/x.causal: …" }
```

## Edit scripts (ops)

`causal apply` and MCP's `apply_ops` take the same format:

```json
{
  "version": 1,
  "ops": [
    { "op": "addChapter", "title": "Act Four · Afterword" },
    { "op": "addCard", "chapter": "Act Four · Afterword", "title": "S10 Autumn Visitor",
      "kind": "ending", "summary": "Lu Zhou arrives as promised to see the little stove.", "body": "…", "after": "S09 Homecoming" },
    { "op": "connect", "from": "S09 Homecoming", "to": "S10 Autumn Visitor", "label": "The autumn promise" }
  ]
}
```

- Cards, chapters, characters, places, and story facts can be named or given by UUID; a duplicate name fails with the candidates listed.
- Ops run in order and stop at the first failure, with the index and op name in the error; applied changes can be left unsaved.
- `causal apply --dry-run` works everything out without writing.

| op | Required | Optional |
| --- | --- | --- |
| `updateHeader` | — | `title` `logline` |
| `arrangeCanvas` | — | `columns` (default 3) |
| `addChapter` | `title` | `summary` |
| `updateChapter` | `chapter` | `title` `summary` |
| `deleteChapter` | `chapter` | — |
| `addCard` | `title` | `chapter` `summary` `body` `kind` `status` `isEntry` `after` `index` `characters` `places` `settings` |
| `updateCard` | `card` | `title` `summary` `body` `kind` `status` `isEntry` `chapter` `characters` `places` `annotation` |
| `moveCard` | `card` | `chapter` `index` |
| `deleteCard` | `card` | — |
| `setEntry` | `card` `isEntry` | — |
| `connect` | `from` `to` | `kind` `label` `condition` `mainline` |
| `updateEdge` | `edge` | `label` `condition` `kind` `mainline` |
| `deleteEdge` | `edge` | — |
| `addCharacter` | `name` | `summary` `notes` |
| `updateCharacter` | `character` | `name` `summary` `notes` |
| `deleteCharacter` | `character` | — |
| `addRelation` | `from` `to` `kind` | — |
| `addPlace` | `name` | `summary` `notes` |
| `updatePlace` | `place` | `name` `summary` `notes` |
| `addSetting` | `title` | `text` `confirmed` `locked` |
| `updateSetting` | `setting` | `title` `text` `confirmed` `locked` |
| `attachSetting` / `detachSetting` | `setting` `card` | — |
| `deleteSetting` | `setting` | — |

`kind` takes `event` / `choice` / `ending`; `status` takes `draft` / `idea`; edge `kind` takes `cause` / `choice` / `condition` / `plain`; relation `kind` takes `father` `mother` `child` `elderBrother` `youngerBrother` `elderSister` `youngerSister` `sibling` `grandparent` `spouse` `lover` `friend` `mentor` `student` `rival` `enemy`.

## Connecting over MCP

```bash
causal mcp                     # the client calls open_project to pick a package
causal mcp --package /path/to/sample.causal   # pin one package
```

The default is stdio with newline-delimited JSON-RPC 2.0. `initialize` declares `tools` / `resources` / `prompts`, and the supported methods are `tools/list`, `tools/call`, `resources/list`, `resources/read`, `prompts/list`, `prompts/get`, and `ping`.

**Leave out `--package`**: the client calls `open_project` first, and every later read and write in that process acts on that package. The `causal` below is a release build, so substitute the absolute path on your machine.

### HTTP / SSE + token

Remote machines, containers, and clients that accept a URL can use HTTP. stdio stays the default, so HTTP transport has to be switched on and always carries a token:

```bash
export CAUSAL_MCP_TOKEN="$(openssl rand -hex 24)"
causal mcp --transport http --host 127.0.0.1 --port 8765
# shorthand
causal mcp --http --port 8765
```

The token comes from `CAUSAL_MCP_TOKEN`, `--token`, or `--token-file`, with the environment variable the safest of the three, and it has no place in a URL. The server binds `127.0.0.1` only. For access from another machine, put a reverse proxy such as Nginx or Caddy in front with TLS and point `--host` at an address the proxy can reach; the service itself does no TLS.

```bash
# liveness, no token needed
curl -s http://127.0.0.1:8765/health

# initialize, and note the Mcp-Session-Id response header
curl -i -X POST http://127.0.0.1:8765/mcp \
  -H "Authorization: Bearer $CAUSAL_MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

# later requests carry the session header
SID="<value from the response header above>"
curl -s -X POST http://127.0.0.1:8765/mcp \
  -H "Authorization: Bearer $CAUSAL_MCP_TOKEN" \
  -H "Mcp-Session-Id: $SID" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

# progress over SSE: ask for text/event-stream in Accept
curl -N -X POST http://127.0.0.1:8765/mcp \
  -H "Authorization: Bearer $CAUSAL_MCP_TOKEN" \
  -H "Mcp-Session-Id: $SID" \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"apply_ops","arguments":{"ops":[...]},"_meta":{"progressToken":"p1"}}}'

# end the session
curl -i -X DELETE http://127.0.0.1:8765/mcp \
  -H "Authorization: Bearer $CAUSAL_MCP_TOKEN" \
  -H "Mcp-Session-Id: $SID"
```

How it behaves:

- A missing or wrong token returns `401` with `WWW-Authenticate: Bearer`, and the comparison is constant-time.
- `initialize` creates a session and returns `Mcp-Session-Id`, which every later request carries. An unknown session returns `404`; `DELETE` ends the session.
- `POST /mcp` wants `Content-Type: application/json`. With `Accept: text/event-stream` the progress and the final response arrive as SSE, otherwise as plain JSON.
- `GET /mcp` returns `405` (the older `GET /sse` was never implemented), while `GET /health` returns `ok` for liveness checks.
- Request bodies stop at 8MB and `Transfer-Encoding: chunked` is not supported yet, so `Content-Length` is required.
- Each session gets its own `MCPState`, so two clients calling `open_project` never collide; cross-process writes still go through `.write.lock` and `PackageStamp`.

```bash
# from the repository root: point C at the release CLI
C="$PWD/Packages/CausalityCore/.build/release/causal"
```

### Codex

```bash
codex mcp add causal -- "$C" mcp
codex mcp list
codex mcp get causal
```

Codex asks for approval on MCP tool calls by default; approve once in the session. For a headless smoke test, use
`codex exec --dangerously-bypass-approvals-and-sandbox ...`.

Lands in `~/.codex/config.toml`:

```toml
[mcp_servers.causal]
command = "/path/to/causal"
args = ["mcp"]
```

### Hermes

```bash
hermes config set mcp_servers.causal.command "$C"
hermes config set mcp_servers.causal.args '["mcp"]'
hermes config set mcp_servers.causal.enabled true
hermes config get mcp_servers
hermes mcp test causal
```

Lands in `~/.hermes/config.yaml`:

```yaml
mcp_servers:
  causal:
    command: /path/to/causal
    args: [mcp]
    enabled: true
```

### Pi

```bash
pi mcp add causal -- "$C" mcp
pi mcp list
```

Lands in `~/.pi/agent/mcp.json` (use `pi mcp add -l` for project level):

```json
{"mcpServers": {"causal": {"command": "/path/to/causal", "args": ["mcp"]}}}
```

`pi mcp list` really connects once, so you should see `causal: connected, 15 tools` and a note that it `offers resources`.

### OpenClaw

```bash
openclaw mcp add causal --command /path/to/causal --arg mcp
openclaw mcp doctor causal --probe
```

Without an `openclaw` executable on this machine, add the entry in the Control UI under Settings → MCP using the `mcp.servers` structure above, with transport set to Stdio.

It lives under `mcp.servers` in `openclaw.json` (the Control UI's Settings → MCP adds it too, transport Stdio):

```json5
{
  mcp: {
    servers: {
      causal: { command: "/path/to/causal", args: ["mcp"] },
    },
  },
}
```

### DSH (DeepSeek Harness)

Edit `~/.dsh/profiles/desktop/cordis.patch.yml`, add an entry to the `- insert:` list at the same level as `mcp-blender`, then restart DeepSeek Harness. The MCP management plugin loads it on startup:

```yaml
    - id: mcp-causal
      name: "@deepseek-ai/dsh-mcp-client"
      config:
        serverName: causal
        transport: stdio
        command: "/path/to/causal"
        args:
          - mcp
        env: {}
        toolCallTimeoutMs: 300000
        failOnStartupError: false
```

### Generic JSON clients

```json
{
  "mcpServers": {
    "causal": { "command": "/path/to/causal", "args": ["mcp"] }
  }
}
```

| Tool | Purpose |
| --- | --- |
| `open_project {path}` | Open a project package |
| `save_project {path?}` | The only place changes land; a package changed by another program is refused, so pass a new path |
| `project_info {}` | Summary, counts, validation, `dirty` |
| `project_export {}` | Full project.json |
| `list_chapters {}` / `list_cards {chapter?}` | Chapters / cards |
| `get_card {card}` | One card's full text and what it references |
| `list_entities {kind}` | Characters / places / story facts |
| `apply_ops {ops, dryRun?}` | Changes memory and sets `dirty`; waits for `save_project` |
| `import_markdown {path? markdown? title?}` | Text storyboard → new project (not yet saved) |
| `validate {}` / `outline {format?}` | Validation / outline |
| `history {steps?}` / `undo {steps?}` / `redo {steps?}` | Snapshots, step back, reapply |

Resources: `causal://project`, `causal://outline`, `causal://card/{uuid}`, `causal://chapter/{uuid}`, `causal://character/{uuid}`. Prompts: `polish-card`, `find-broken`, `add-causality`.

A typical run: `open_project` → `list_chapters` / `get_card` → `apply_ops` → `validate` → `save_project`. Consecutive `apply_ops` calls all stay in memory and the last `save_project` writes them out; `project_info`'s `dirty` reports changes that have not been saved yet.

`apply_ops` runs in batches of 20. When the request carries `params._meta.progressToken`, each finished batch emits a `notifications/progress` with `progress` and `total`. Sending `notifications/cancelled {requestId}` stops at the end of the current batch: the cancelled changes never reach memory, and `save_project` never sees them.

Outside MCP, a `.causal` is an ordinary folder: `project.json` is versioned Codable JSON and `assets/` holds the original images. To edit the files without the CLI, read the whole structure first and write it back atomically.
