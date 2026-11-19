# 命令行接口（causal）

给脚本、CI 和 MCP 服务器用的稳定入口。所有读写都走模型层同一套代码，跟 App 里看到的完全一致。

```bash
cd Packages/CausalityCore
swift build -c release          # 产物在 .build/release/causal
```

装到 PATH 里可以软链或直接拷：

```bash
ln -sf "$PWD/.build/release/causal" /usr/local/bin/causal
```

## 命令

| 命令 | 作用 |
| --- | --- |
| `causal import <故事板.md> [输出.causal] [--title 标题] [--lang en\|ja\|zh-Hant]` | 把文字故事板转成工程包；`--lang` 决定表述语言（英文/日文表头、卡片三段标签、CLI 提示） |
| `causal info <工程包.causal>` | 打印章节、卡片、因果、灵感卡 |
| `causal validate <工程包.causal>` | 跑模型层校验，有问题返回 1 |
| `causal outline <工程包.causal>` | 打印推导出的大纲（Markdown） |
| `causal apply <工程包.causal> --ops ops.json` | 按脚本改工程，写回包 |
| `causal undo <工程包.causal> [--steps N]` | 撤回历史快照 |
| `causal redo <工程包.causal> [--steps N]` | 重做刚撤回的状态 |
| `causal export <工程包.causal> [--out 文件]` | 导出完整 project.json；先过契约 |
| `causal contract <导出.json>` | 按 schemaVersion 校验必填字段 |
| `causal audit <工程包.causal> [--all]` | 跑 N01–N21 体检；有错误返回 1 |
| `causal branch <工程包.causal> [--to 结局] [--mode segments\|per-path]` | 分支梗概 |
| `causal reach <工程包.causal> --from <卡片>` | 从一张卡往后能到哪些结局与步数 |
| `causal play <工程包.causal> [--choices 1,1] [--out 试读稿.md]` | 单路径试玩与试读稿 |
| `causal thread <工程包.causal>` | 列出线索与脊柱上的点 |
| `causal mcp [--package 工程包] [--transport stdio\|http]` | 起 MCP 服务器；默认 stdio，HTTP 需 token |

除 `export` 与 `mcp` 外都接受 `--json`，此时 stdout 只有一个 JSON 对象。

退出码：`0` 成功，`1` 失败（文件读不到、包打不开、校验不通过），`2` 用法错误。

## 语言（`--lang`）

CLI 的提示、报告、卡片三段标签与 MCP 服务端文案共用 `CausalityCore` 的一份词条表，语言由 `--lang` 决定。

- 可用值：`zh-Hans`、`en`、`ja`、`zh-Hant`；也认带地区的写法（`zh-TW` / `zh-HK` / `zh-MO` → `zh-Hant`，`en-US` → `en`，`ja-JP` → `ja`）。
- 位置：子命令前后都行，`--lang en` 与 `--lang=en` 等价。
- 优先级：显式 `--lang` > 故事板表头推断 > `LANG` 的语言前缀 > 默认 `zh-Hans`。
- 表头：故事板导入永远认中文表头，再加当前语言那一套（`Beat and Timing` / `ビートとタイミング` / `節點與時機`）。读繁体表头的文档要认出表头，就写 `--lang zh-Hant`；同一个参数也决定卡片正文的三段标签写成 `Sees / Does / Leaves` 还是 `見る / する / 残る`。
- MCP：`causal mcp --lang en` 起服务后，`tools/list` 的描述、`tools/call` 的错误文本、HTTP 传输的握手与鉴权提示都出英文。

```bash
causal --lang ja validate 工程.causal      # 子命令前
causal mcp --lang en                      # 子命令后
causal mcp --transport http --lang ja     # 与其它参数混写
```

## import 认什么

导入器认中文、英文、日文、繁体四种表头（`节点与时机`、`Beat and Timing`、`ビートとタイミング`、`節點與時機`），并按表头语言把卡片正文的三段标签写成 `Sees / Does / Leaves`、`見る / する / 残る`、`眼前 / 動手 / 留下`。表头无法判断时可用 `--lang en|ja|zh-Hant` 显式指定；CLI 自己的提示、报告与卡片三段标签跟随同一套词条（见上一节「语言」）。

默认自动识别：含 `| 节点与时机 |` 表的文档走故事板导入，其余走普通 Markdown 导入。`--format storyboard|prose` 可以强制。

**普通 Markdown**：`#` 是项目名，`##` 是章，`###`/`####` 是场，其余段落进正文；没有 `###` 时一章并成一场。`## 人物` / `## 地点` / `## 设定` 下的表或 `- **名字**：说明` 会建成对应实体，并按名字挂到出现的场次。

```markdown
# 雨夜来信

**一句话梗概。**

## 第一幕 · 来信

### 第一场 信封

林远在雨夜收到一封信。

## 人物

| 名字 | 简介 |
|---|---|
| 林远 | 收信人。 |
```

**故事板表格**：

```markdown
# 《镇名》开篇故事板        ← 一级标题，没给 --title 时用来命名

**一段梗概。**               ← 项目梗概（AI 上下文会带）

## 第一幕 · 小标题           ← 一章

| 节点与时机 | 玩家眼前发生什么 | 玩家亲手做什么 | 留下什么，怎样引出下一场 |
|---|---|---|---|
| S01 入城，当日下午 | … | … | … |
```

- 表格第一行是表头，第一列「编号 短名，时机」拆成卡片标题与注释；
- 其余三列写进卡片正文，前缀分别是 `眼前：` / `动手：` / `留下：`；
- 卡片按行序用因果连起来，线上的文字取「留下什么」的首句；
- 表头不是「节点与时机」的表（例如四向表）落成灵感卡，不进故事板；
- 章节里的 `- **小标题**：正文` 也落成灵感卡；
- 人物、地点、事实设定只认文内 `## 人物` / `## 地点` / `## 设定` 段；没有就不建，不再预置示例库。
- 普通 Markdown 导入的 JSON 带 `"mode": "prose"` 与一条 `notes`（几章几场）。

## JSON 结构

`import` 与 `info` 的公共部分：

```json
{
  "ok": true,
  "command": "import",
  "package": "/abs/path/示例.causal",
  "title": "示例 · 开篇故事板",
  "logline": "一个通用示例工程：从主角搬进新住处，写到第一次自己出远门。…",
  "revision": 0,
  "metadataBytes": 26995,
  "counts": { "chapters": 3, "cards": 9, "ideas": 8, "edges": 8,
              "characters": 4, "places": 7, "settings": 4 },
  "chapters": [ { "id": "…", "title": "第一幕 · 落脚", "cards": 2 } ],
  "warnings": []
}
```

`info` 另外带 `cards` 与 `edges`：

```json
"cards": [{
  "id": "…", "title": "S01 入城", "kind": "event", "status": "draft",
  "chapter": "第一幕 · 落脚",
  "summary": "雨刚停，主角带着行李来投奔租房的房东。…",
  "body": "眼前：…\n\n动手：…\n\n留下：…",
  "characters": ["房东"], "places": ["小院"], "settings": [],
  "outgoing": 1, "incoming": 0
}],
"edges": [{ "id": "…", "from": "S01 入城", "to": "S02 看见手艺",
            "kind": "plain", "label": "拿到自己的房门钥匙", "condition": "" }]
```

失败时只有两个字段：

```json
{ "ok": false, "error": "打不开 /path/x.causal：…" }
```

## 编辑脚本（ops）

`causal apply` 与 MCP 的 `apply_ops` 吃同一份格式：

```json
{
  "version": 1,
  "ops": [
    { "op": "addChapter", "title": "第四幕 · 后记" },
    { "op": "addCard", "chapter": "第四幕 · 后记", "title": "S10 秋日来客",
      "kind": "ending", "summary": "陆舟如约来看那口小炉。", "body": "…", "after": "S09 归家" },
    { "op": "connect", "from": "S09 归家", "to": "S10 秋日来客", "label": "秋日之约" }
  ]
}
```

- 引用卡片、章节、人物、地点、事实设定，写名字或写 UUID 都行，重名会报错并列出候选；
- 按顺序执行，第几条失败就停在那一条，报错带序号与 op 名，已执行的改动可以选择不保存；
- `causal apply --dry-run` 只演算不写盘。

| op | 必填 | 可选 |
| --- | --- | --- |
| `updateHeader` | — | `title` `logline` |
| `arrangeCanvas` | — | `columns`（默认 3） |
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

`kind` 取 `event` / `choice` / `ending`；`status` 取 `draft` / `idea`；连线 `kind` 取 `cause` / `choice` / `condition` / `plain`；关系 `kind` 取 `father` `mother` `child` `elderBrother` `youngerBrother` `elderSister` `youngerSister` `sibling` `grandparent` `spouse` `lover` `friend` `mentor` `student` `rival` `enemy`。

## 接 MCP

```bash
causal mcp                     # 由客户端调 open_project 选包
causal mcp --package /path/to/示例.causal   # 固定一个包
```

默认是 stdio、换行分隔的 JSON-RPC 2.0。`initialize` 声明 `tools` / `resources` / `prompts`；支持 `tools/list`、`tools/call`、`resources/list`、`resources/read`、`prompts/list`、`prompts/get`、`ping`。

**推荐不带 `--package`**：客户端先 `open_project`，之后同一进程里的读写都作用在那个包上。`causal` 是 release 产物，换成你机器上的绝对路径：

### HTTP / SSE + token

远程机器、容器或支持 URL 的客户端可以走 HTTP。默认只开 stdio，HTTP 传输需要显式打开，并且必须带 token：

```bash
export CAUSAL_MCP_TOKEN="$(openssl rand -hex 24)"
causal mcp --transport http --host 127.0.0.1 --port 8765
# 等价简写
causal mcp --http --port 8765
```

token 从 `CAUSAL_MCP_TOKEN`、`--token` 或 `--token-file` 读，推荐环境变量；不要放进 URL。默认只绑 `127.0.0.1`。要跨机器访问，用 Nginx/Caddy 之类的反向代理加 TLS，再把 `--host` 改成代理能连的地址；本服务自己不做 TLS。

```bash
# 探活，不需要 token
curl -s http://127.0.0.1:8765/health

# initialize，记下响应头 Mcp-Session-Id
curl -i -X POST http://127.0.0.1:8765/mcp \
  -H "Authorization: Bearer $CAUSAL_MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

# 后续请求带会话头
SID="<上一步响应头里的值>"
curl -s -X POST http://127.0.0.1:8765/mcp \
  -H "Authorization: Bearer $CAUSAL_MCP_TOKEN" \
  -H "Mcp-Session-Id: $SID" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

# 进度走 SSE：Accept 里带 text/event-stream
curl -N -X POST http://127.0.0.1:8765/mcp \
  -H "Authorization: Bearer $CAUSAL_MCP_TOKEN" \
  -H "Mcp-Session-Id: $SID" \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"apply_ops","arguments":{"ops":[...]},"_meta":{"progressToken":"p1"}}}'

# 结束会话
curl -i -X DELETE http://127.0.0.1:8765/mcp \
  -H "Authorization: Bearer $CAUSAL_MCP_TOKEN" \
  -H "Mcp-Session-Id: $SID"
```

行为约定：

- 没带 token、token 错误都返回 `401`，带 `WWW-Authenticate: Bearer`；比较用常量时间。
- `initialize` 建会话并返回 `Mcp-Session-Id`；之后每个请求都带它。会话不存在返回 `404`；`DELETE` 结束会话。
- `POST /mcp` 的 `Content-Type` 要是 `application/json`；`Accept: text/event-stream` 时进度和最终响应用 SSE 发，否则用普通 JSON。
- `GET /mcp` 返回 `405`（旧版 `GET /sse` 没有实现）；`GET /health` 返回 `ok`，方便探活。
- 请求体上限 8MB，暂不支持 `Transfer-Encoding: chunked`；`Content-Length` 必填。
- 每个会话一个 `MCPState`，两个客户端各自 `open_project` 不会串项目；跨进程写盘仍走 `.write.lock` 和 `PackageStamp`。

```bash
# 从仓库根目录：把 C 指到 release 版命令行
C="$PWD/Packages/CausalityCore/.build/release/causal"
```

### Codex

```bash
codex mcp add causal -- "$C" mcp
codex mcp list
codex mcp get causal
```

Codex 的 MCP 工具调用默认需要审批；交互里批准一次即可，无头烟雾测试用
`codex exec --dangerously-bypass-approvals-and-sandbox ...`。

落在 `~/.codex/config.toml`：

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

落在 `~/.hermes/config.yaml`：

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

落在 `~/.pi/agent/mcp.json`（项目级用 `pi mcp add -l`）：

```json
{"mcpServers": {"causal": {"command": "/path/to/causal", "args": ["mcp"]}}}
```

`pi mcp list` 会真的连一次：应看到 `causal: connected, 15 tools`，并标注 `offers resources`。

### OpenClaw

```bash
openclaw mcp add causal --command /path/to/causal --arg mcp
openclaw mcp doctor causal --probe
```

本机若没有 `openclaw` 可执行文件，先在 Control UI 的 Settings → MCP 里按上面的 `mcp.servers` 结构加，transport 选 Stdio。

定义在 `openclaw.json` 的 `mcp.servers`（Control UI 的 Settings → MCP 也能加，transport 选 Stdio）：

```json5
{
  mcp: {
    servers: {
      causal: { command: "/path/to/causal", args: ["mcp"] },
    },
  },
}
```

### DSH（DeepSeek Harness）

编辑 `~/.dsh/profiles/desktop/cordis.patch.yml`，在 `- insert:` 列表里加一项（与 `mcp-blender` 同一层），然后重启 DeepSeek Harness。MCP 管理插件会在启动时加载：

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

### 通用 JSON 客户端

```json
{
  "mcpServers": {
    "causal": { "command": "/path/to/causal", "args": ["mcp"] }
  }
}
```

| 工具 | 作用 |
| --- | --- |
| `open_project {path}` | 打开工程包 |
| `save_project {path?}` | 唯一落盘点；磁盘被别的程序改过会拒绝覆盖，要给新 path |
| `project_info {}` | 摘要、计数、校验、`dirty` |
| `project_export {}` | 完整 project.json |
| `list_chapters {}` / `list_cards {chapter?}` | 章节 / 卡片 |
| `get_card {card}` | 一张卡的全文与引用 |
| `list_entities {kind}` | 人物 / 地点 / 事实设定 |
| `apply_ops {ops, dryRun?}` | 只改内存并置 `dirty`，等 `save_project` |
| `import_markdown {path? markdown? title?}` | 文字故事板 → 新项目（未落盘） |
| `validate {}` / `outline {format?}` | 校验 / 大纲 |
| `history {steps?}` / `undo {steps?}` / `redo {steps?}` | 快照、撤回、重做 |

资源：`causal://project`、`causal://outline`、`causal://card/{uuid}`、`causal://chapter/{uuid}`、`causal://character/{uuid}`。提示词：`polish-card`、`find-broken`、`add-causality`。

典型调用序：`open_project` → `list_chapters` / `get_card` → `apply_ops` → `validate` → `save_project`。`apply_ops` 连续调用都留在内存里，最后一次 `save_project` 落盘；`project_info` 的 `dirty` 表示还没保存。

`apply_ops` 每 20 条一批执行。请求带 `params._meta.progressToken` 时，每批结束发一条 `notifications/progress`（`progress` / `total`）。发 `notifications/cancelled {requestId}` 会在当前批结束时停下，取消的改动不写回内存，`save_project` 也不会看到它们。

MCP 之外，`.causal` 也是普通目录：`project.json` 是版本化 Codable JSON，`assets/` 放原图。想绕过命令行直接改文件，读完整个结构再原子写回即可。
