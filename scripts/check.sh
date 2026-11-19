#!/bin/bash
# 一次跑完模型层测试、命令行自检、App 构建与 App 测试。CI 与本机验收都用这一条。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== 前置：词条表一致性 =="
for l in zh-Hans en ja zh-Hant; do
  for f in Localizable.strings Localizable.stringsdict; do
    src="Packages/CausalityCore/Sources/CausalityCore/Resources/$l.lproj/$f"
    dst="Sources/Causality/$l.lproj/$f"
    if [ -f "$src" ] && ! cmp -s "$src" "$dst"; then
      echo "  ✗ $l.lproj/$f 两份不一致，先跑 scripts/sync-strings.sh"
      exit 1
    fi
  done
done
echo "  四份词条表一致"

echo "== 1/5 模型层测试 =="
(cd Packages/CausalityCore && swift test)

echo "== 2/5 命令行自检 =="
(cd Packages/CausalityCore && swift build -c release --product causal)
# CLI 默认跟随 LANG；自检固定简体中文，英文导入用例单独用表头/--lang 验证。
export LANG=zh_CN.UTF-8
CLI="$ROOT/Packages/CausalityCore/.build/release/causal"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/故事板.md" <<'MD'
# 《自检镇》开篇

**一段梗概。**

## 第一幕 · 入镇

| 节点与时机 | 玩家眼前发生什么 | 玩家亲手做什么 | 留下什么，怎样引出下一场 |
|---|---|---|---|
| S01 入镇，当日 | 雨停了。 | 放下行囊。 | 拿到钥匙。 |
| S02 见法，次日 | 丹师来访。 | 托着叶片。 | 学了引息诀。 |
MD

"$CLI" import "$TMP/故事板.md" "$TMP/自检.causal" --json > "$TMP/import.json"
cat > "$TMP/散文.md" <<'MD'
# 雨夜来信

**一句话梗概。**

## 第一幕

### 第一场 信封

林远收到一封信。

### 第二场 钟楼

他去了钟楼。

## 第二幕

### 第三场 重逢

姐姐在等他。

## 人物

| 名字 | 简介 |
|---|---|
| 林远 | 收信人。 |
MD
"$CLI" import "$TMP/散文.md" "$TMP/散文.causal" --json > "$TMP/prose-import.json"
cat > "$TMP/故事板-英文.md" <<'MD'
# Lantern

## Act One

| Beat and Timing | What the player sees | What the player does | What remains |
|---|---|---|---|
| S01 Arrival, morning | Rain stops. | Sets down the bag. | Gets a key. |
MD
"$CLI" import "$TMP/故事板-英文.md" "$TMP/英文.causal" --json > "$TMP/en-import.json"
"$CLI" validate "$TMP/自检.causal" --json > "$TMP/validate.json"
"$CLI" outline "$TMP/自检.causal" --to "S02 见法" > "$TMP/outline.md"
printf '{"ops":[{"op":"addChapter","title":"第二幕"}]}' > "$TMP/ops.json"
"$CLI" apply "$TMP/自检.causal" --ops "$TMP/ops.json" --json > "$TMP/apply.json"
"$CLI" history "$TMP/自检.causal" --json > "$TMP/history.json"
"$CLI" undo "$TMP/自检.causal" --json > "$TMP/undo.json"
"$CLI" redo "$TMP/自检.causal" --steps 1 --json > "$TMP/redo.json"
"$CLI" export "$TMP/自检.causal" --out "$TMP/export.json" --json > "$TMP/export-result.json"
"$CLI" contract "$TMP/export.json" --json > "$TMP/contract.json"
python3 - "$TMP/export.json" "$TMP/export-broken.json" <<'JSONCHECK'
import json, sys
source, target = sys.argv[1], sys.argv[2]
data = json.load(open(source))
data.pop("logline", None)
data["nodes"][0].pop("body", None)
json.dump(data, open(target, "w"), ensure_ascii=False)
JSONCHECK
if "$CLI" contract "$TMP/export-broken.json" > "$TMP/contract-broken.txt" 2>&1; then
  echo "  ✗ 缺字段没有被契约拦下"
  exit 1
fi
if "$CLI" audit "$ROOT/case/河灯里的字.causal" --json > "$TMP/audit-lantern.json"; then
  echo "  ✗ 河灯体检应有错误"
  exit 1
fi
if "$CLI" audit "$ROOT/case/示例 · 开篇故事板.causal" --json > "$TMP/audit-sample.json"; then
  echo "  ✗ 示例体检应有错误"
  exit 1
fi
"$CLI" play "$ROOT/case/河灯里的字.causal" --choices 1,1 --json > "$TMP/play.json"
"$CLI" thread "$TMP/自检.causal" --json > "$TMP/thread.json"
python3 - "$CLI" "$TMP/自检.causal" <<'MCPCHECK'
import json, subprocess, sys, time
cli, pkg = sys.argv[1], sys.argv[2]
proc = subprocess.Popen([cli, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, bufsize=1)

def read_response(i):
    progress = []
    while True:
        line = proc.stdout.readline()
        if not line:
            raise RuntimeError("MCP 提前退出")
        msg = json.loads(line)
        if msg.get("method") == "notifications/progress":
            progress.append(msg["params"])
            continue
        if msg.get("id") == i:
            return msg, progress

def req(i, method, params=None):
    msg = {"jsonrpc": "2.0", "id": i, "method": method}
    if params is not None:
        msg["params"] = params
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()
    return read_response(i)[0]

def tool_call(i, name, args, token=None):
    params = {"name": name, "arguments": args}
    if token is not None:
        params["_meta"] = {"progressToken": token}
    proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": i, "method": "tools/call",
                                 "params": params}) + "\n")
    proc.stdin.flush()
    return read_response(i)

def tool_text(msg):
    return msg.get("result", {}).get("content", [{}])[0].get("text", "")

caps = req(1, "initialize", {"protocolVersion": "2024-11-05"})["result"]["capabilities"]
assert "resources" in caps and "prompts" in caps
req(2, "tools/call", {"name": "open_project", "arguments": {"path": pkg}})
resources = req(3, "resources/list")["result"]["resources"]
assert any(r["uri"].startswith("causal://card/") for r in resources)
prompts = req(4, "prompts/list")["result"]["prompts"]
assert {p["name"] for p in prompts} == {"polish-card", "find-broken", "add-causality"}
card = next(r for r in resources if r["uri"].startswith("causal://card/"))
text = req(5, "resources/read", {"uri": card["uri"]})["result"]["contents"][0]["text"]
assert card["name"] in text

progress_ops = [{"op": "addChapter", "title": f"进度 {i}"} for i in range(40)]
msg, progress = tool_call(6, "apply_ops", {"ops": progress_ops}, token="ci")
assert len(progress) >= 2 and progress[-1]["total"] == 40
assert json.loads(tool_text(msg))["ok"] is True

req(7, "tools/call", {"name": "open_project", "arguments": {"path": pkg}})
info = json.loads(tool_text(req(8, "tools/call", {"name": "project_info", "arguments": {}})))
baseline = info["counts"]["chapters"]
big = [{"op": "addChapter", "title": f"取消 {i}"} for i in range(5000)]
proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 9, "method": "tools/call",
                             "params": {"name": "apply_ops", "arguments": {"ops": big},
                                        "_meta": {"progressToken": "ci-cancel"}}}) + "\n")
proc.stdin.flush()
time.sleep(0.1)
proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/cancelled",
                             "params": {"requestId": 9}}) + "\n")
proc.stdin.flush()
msg, _ = read_response(9)
cancelled = "取消" in tool_text(msg) or msg.get("error", {}).get("code") == -32800
assert cancelled, msg
info = json.loads(tool_text(req(10, "tools/call", {"name": "project_info", "arguments": {}})))
assert info["counts"]["chapters"] == baseline

proc.stdin.close()
proc.wait(timeout=5)
print("  ✓ MCP resources / prompts")
print("  ✓ MCP progress / cancellation")
MCPCHECK

python3 - "$CLI" "$TMP/自检.causal" <<'HTTPCHECK'
import http.client
import json
import os
import socket
import subprocess
import sys
import threading
import time

cli, pkg = sys.argv[1], sys.argv[2]
token = "ci-http-token"


def free_port():
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


port = free_port()
env = dict(os.environ)
env["CAUSAL_MCP_TOKEN"] = token
proc = subprocess.Popen(
    [cli, "mcp", "--transport", "http", "--host", "127.0.0.1", "--port", str(port)],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env=env,
)


def request(method, path, body=None, auth=True, bearer=None, session=None, accept=None):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=20)
    headers = {}
    if auth:
        headers["Authorization"] = "Bearer " + (bearer or token)
    if session:
        headers["Mcp-Session-Id"] = session
    if accept:
        headers["Accept"] = accept
    payload = None
    if body is not None:
        payload = body if isinstance(body, (bytes, str)) else json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    conn.request(method, path, body=payload, headers=headers)
    response = conn.getresponse()
    data = response.read()
    result = (response.status, dict(response.getheaders()), data)
    conn.close()
    return result


try:
    for _ in range(100):
        try:
            status, _, body = request("GET", "/health", auth=False)
            if status == 200 and body == b"ok":
                break
        except OSError:
            pass
        if proc.poll() is not None:
            raise RuntimeError("HTTP 服务提前退出：" + proc.stderr.read())
        time.sleep(0.05)
    else:
        raise RuntimeError("HTTP 服务没有起来")

    initialize = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}
    status, _, _ = request("POST", "/mcp", initialize, auth=False)
    assert status == 401, status
    status, _, _ = request("POST", "/mcp", initialize, bearer="wrong-token")
    assert status == 401, status
    status, headers, body = request("POST", "/mcp", initialize)
    assert status == 200, status
    session = headers.get("Mcp-Session-Id") or headers.get("mcp-session-id")
    assert session, headers
    assert json.loads(body)["result"]["serverInfo"]["name"] == "causal"

    status, _, body = request(
        "POST", "/mcp", {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}, session=session
    )
    assert status == 200, status
    assert len(json.loads(body)["result"]["tools"]) == 15

    status, _, body = request(
        "POST",
        "/mcp",
        {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "open_project", "arguments": {"path": pkg}},
        },
        session=session,
    )
    assert status == 200, status
    assert json.loads(body)["result"]["isError"] is False

    # 同进程的第二个会话不应看到第一个会话打开的项目。
    status, headers, _ = request("POST", "/mcp", initialize)
    other = headers.get("Mcp-Session-Id") or headers.get("mcp-session-id")
    assert other and other != session
    status, _, body = request(
        "POST",
        "/mcp",
        {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "project_info", "arguments": {}}},
        session=other,
    )
    assert status == 200, status
    assert json.loads(body)["result"]["isError"] is True

    ops = [{"op": "addChapter", "title": f"HTTP {i}"} for i in range(40)]
    status, headers, body = request(
        "POST",
        "/mcp",
        {
            "jsonrpc": "2.0",
            "id": 5,
            "method": "tools/call",
            "params": {"name": "apply_ops", "arguments": {"ops": ops}, "_meta": {"progressToken": "http-ci"}},
        },
        session=session,
        accept="text/event-stream",
    )
    assert status == 200, status
    assert headers.get("Content-Type", "").startswith("text/event-stream"), headers
    events = [json.loads(line[6:]) for line in body.decode().splitlines() if line.startswith("data: ")]
    assert any(event.get("method") == "notifications/progress" for event in events), events[:2]
    final = next(event for event in events if event.get("id") == 5)
    assert final["result"]["isError"] is False, final

    status, _, body = request(
        "POST",
        "/mcp",
        {"jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": {"name": "project_info", "arguments": {}}},
        session=session,
    )
    baseline = json.loads(json.loads(body)["result"]["content"][0]["text"])["counts"]["chapters"]

    many = [{"op": "addChapter", "title": f"取消 {i}"} for i in range(5000)]
    cancelled = {}

    def slow_apply():
        status, _, body = request(
            "POST",
            "/mcp",
            {
                "jsonrpc": "2.0",
                "id": 7,
                "method": "tools/call",
                "params": {"name": "apply_ops", "arguments": {"ops": many}, "_meta": {"progressToken": "http-cancel"}},
            },
            session=session,
            accept="text/event-stream",
        )
        cancelled["status"] = status
        cancelled["body"] = body

    worker = threading.Thread(target=slow_apply)
    worker.start()
    time.sleep(0.1)
    status, _, _ = request(
        "POST",
        "/mcp",
        {"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": 7}},
        session=session,
    )
    assert status == 202, status
    worker.join(timeout=30)
    assert not worker.is_alive(), "HTTP 取消请求没有结束"
    events = [json.loads(line[6:]) for line in cancelled["body"].decode().splitlines() if line.startswith("data: ")]
    final = next(event for event in events if event.get("id") == 7)
    assert final["result"]["isError"] is True, final
    assert "取消" in final["result"]["content"][0]["text"], final
    status, _, body = request(
        "POST",
        "/mcp",
        {"jsonrpc": "2.0", "id": 8, "method": "tools/call", "params": {"name": "project_info", "arguments": {}}},
        session=session,
    )
    assert json.loads(json.loads(body)["result"]["content"][0]["text"])["counts"]["chapters"] == baseline

    status, _, body = request(
        "POST", "/mcp", b"{bad json", session=session
    )
    assert status == 400, status
    assert json.loads(body)["error"]["code"] == -32700

    status, _, _ = request("GET", "/mcp", session=session)
    assert status == 405, status

    status, _, _ = request("DELETE", "/mcp", session=session)
    assert status == 204, status
    status, _, _ = request("POST", "/mcp", {"jsonrpc": "2.0", "id": 6, "method": "tools/list"}, session=session)
    assert status == 404, status
finally:
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()

print("  ✓ MCP HTTP + token / session")
print("  ✓ MCP HTTP SSE progress")
HTTPCHECK

python3 - "$TMP" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
checks = []
counts = json.loads((root / "import.json").read_text())["counts"]
checks.append(("导入 2 张卡", counts["cards"] == 2))
checks.append(("校验通过", json.loads((root / "validate.json").read_text())["ok"]))
checks.append(("单路线带说明", "只含通往" in (root / "outline.md").read_text()))
checks.append(("apply 落章", json.loads((root / "apply.json").read_text())["written"]))
checks.append(("history 有快照", len(json.loads((root / "history.json").read_text())["snapshots"]) >= 1))
prose = json.loads((root / "prose-import.json").read_text())
checks.append(("普通 Markdown 自动识别", prose["mode"] == "prose"))
checks.append(("散文导入 2 章 3 场", prose["counts"]["chapters"] == 2 and prose["counts"]["cards"] == 3))
checks.append(("散文导入人物与连线", prose["counts"]["characters"] == 1 and prose["counts"]["edges"] == 2))
english = json.loads((root / "en-import.json").read_text())
checks.append(("英文表头识别", english["mode"] == "storyboard"))
english_body = json.loads((root / "英文.causal" / "project.json").read_text())["nodes"][0]["body"]
checks.append(("英文卡片标签", all(tag in english_body for tag in ("Sees:", "Does:", "Leaves:"))))
checks.append(("undo 回退", json.loads((root / "undo.json").read_text())["ok"]))
checks.append(("redo 重做", json.loads((root / "redo.json").read_text())["ok"]))
checks.append(("export 契约通过", json.loads((root / "contract.json").read_text())["ok"]))
broken = (root / "contract-broken.txt").read_text()
checks.append(("缺 logline 点名", "logline" in broken))
checks.append(("缺正文字段带下标", "nodes[0].body" in broken))
lantern = {f["rule"] for f in json.loads((root / "audit-lantern.json").read_text())["findings"]}
checks.append(("河灯体检 5 条", lantern == {"N01", "N03", "N08", "N15", "N20"}))
sample = {f["rule"] for f in json.loads((root / "audit-sample.json").read_text())["findings"]}
checks.append(("示例体检 3 条", sample == {"N01", "N12", "N21"}))
checks.append(("无结局抑制 N10 / N11", not ({"N10", "N11"} & sample)))
play = json.loads((root / "play.json").read_text())
checks.append(("试玩走到结局", play["finished"] and play["steps"] == 4))
checks.append(("试玩累计字数", play["words"] == 115))
checks.append(("线索命令", json.loads((root / "thread.json").read_text())["ok"]))
failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(("  ✓ " if ok else "  ✗ ") + name)
sys.exit(1 if failed else 0)
PY

echo "== 配色对比度 =="
python3 "$ROOT/scripts/check-theme-contrast.py"

echo "== 3/5 生成 Xcode 工程 =="
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
  echo "  xcodegen 完成"
else
  echo "  跳过：没装 xcodegen"
fi

echo "== 4/5 App 构建 =="
if [ -d Causality.xcodeproj ]; then
  BUILD_LOG="$TMP/xcodebuild.log"
  if ! xcodebuild -project Causality.xcodeproj -scheme Causality -configuration Debug \
    -destination 'platform=macOS' build >"$BUILD_LOG" 2>&1; then
    echo "  xcodebuild 失败："
    grep -n -E "error:|error$" "$BUILD_LOG" | head -40 || true
    echo "  （日志尾部）"
    tail -20 "$BUILD_LOG"
    exit 1
  fi
  echo "  BUILD SUCCEEDED"

  echo "== 5/5 App 测试 =="
  TEST_LOG="$TMP/xcodebuild-test.log"
  if ! xcodebuild test -project Causality.xcodeproj -scheme Causality -configuration Debug \
    -destination 'platform=macOS' >"$TEST_LOG" 2>&1; then
    echo "  App 测试失败："
    grep -n -E "error:|Test \".*\" recorded an issue|XCTAssert" "$TEST_LOG" | head -40 || true
    echo "  （日志尾部）"
    tail -30 "$TEST_LOG"
    exit 1
  fi
  echo "  TEST SUCCEEDED"
else
  echo "  跳过：没有 Causality.xcodeproj"
fi

echo "全部通过"
