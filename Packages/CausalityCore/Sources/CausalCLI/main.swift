import Foundation
import CausalityCore

/// 极简参数表：位置参数 + `--flag` + `--key value` / `--key=value`。
struct Arguments {
    var positional: [String] = []
    var flags: Set<String> = []
    var values: [String: String] = [:]

    init(_ raw: [String]) {
        var index = 0
        while index < raw.count {
            let item = raw[index]
            if item.hasPrefix("--") {
                let body = String(item.dropFirst(2))
                if let equal = body.firstIndex(of: "=") {
                    values[String(body[body.startIndex..<equal])] = String(body[body.index(after: equal)...])
                } else if index + 1 < raw.count, !raw[index + 1].hasPrefix("--") {
                    values[body] = raw[index + 1]
                    index += 1
                } else {
                    flags.insert(body)
                }
            } else {
                positional.append(item)
            }
            index += 1
        }
    }

    var wantsJSON: Bool { flags.contains("json") }

    /// `--lang` 允许出现在子命令前后：入口先把它抽出来，剩下的参数照旧解析。
    static func splittingLanguage(_ raw: [String]) -> (arguments: [String], language: String?) {
        var remaining: [String] = []
        var language: String?
        var index = 0
        while index < raw.count {
            let item = raw[index]
            if item == "--lang" {
                if index + 1 < raw.count, !raw[index + 1].hasPrefix("--") {
                    language = raw[index + 1]
                    index += 2
                    continue
                }
                index += 1
                continue
            }
            if item.hasPrefix("--lang=") {
                language = String(item.dropFirst("--lang=".count))
                index += 1
                continue
            }
            remaining.append(item)
            index += 1
        }
        return (remaining, language)
    }
}

enum Output {
    static func json(_ value: [String: Any]) {
        let data = (try? JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )) ?? Data("{}".utf8)
        print(String(decoding: data, as: UTF8.self))
    }

    static func failure(_ message: String, json: Bool) -> Int32 {
        if json {
            Output.json(["ok": false, "error": message])
        } else {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
        return 1
    }
}

/// 工程摘要：import / info 共用。
func summary(_ project: StoryProject, packageURL: URL? = nil) -> [String: Any] {
    let index = project.makeIndex()
    let cards = project.nodes.filter { $0.status == .draft }
    let ideas = project.nodes.filter { $0.status == .idea }
    var payload: [String: Any] = [
        "title": project.title,
        "logline": project.logline,
        "revision": project.revision,
        "counts": [
            "chapters": project.chapters.count,
            "cards": cards.count,
            "ideas": ideas.count,
            "edges": project.edges.count,
            "characters": project.characters.count,
            "places": project.places.count,
            "settings": project.settings.count,
        ],
        "chapters": project.chapters.map { chapter in
            [
                "id": chapter.id.rawValue.uuidString,
                "title": chapter.title,
                "cards": chapter.order.count,
            ]
        },
        "warnings": ProjectValidator.issues(in: project),
    ]
    if let packageURL {
        payload["package"] = packageURL.path
    }
    _ = index
    return payload
}

/// 每张卡的明细，给 info 用。
func cardDetail(_ project: StoryProject) -> [[String: Any]] {
    let index = project.makeIndex()
    return project.nodes.map { node in
        var item: [String: Any] = [
            "id": node.id.rawValue.uuidString,
            "title": node.title,
            "kind": node.kind.rawValue,
            "status": node.status.rawValue,
            "summary": node.summary,
            "body": node.body,
            "characters": node.characterIDs.compactMap { index.characterByID[$0]?.name },
            "places": node.placeIDs.compactMap { index.placeByID[$0]?.name },
            "settings": project.settings
                .filter { $0.attachedNodeIDs.contains(node.id) }
                .map(\.title),
            "outgoing": (index.outgoing[node.id] ?? []).count,
            "incoming": (index.incoming[node.id] ?? []).count,
        ]
        if let chapterID = node.chapterID, let chapter = index.chapterByID[chapterID] {
            item["chapter"] = chapter.title
        }
        return item
    }
}

func edgesDetail(_ project: StoryProject) -> [[String: Any]] {
    let index = project.makeIndex()
    return project.edges.map { edge in
        [
            "id": edge.id.rawValue.uuidString,
            "from": index.nodeByID[edge.from]?.title ?? edge.from.rawValue.uuidString,
            "to": index.nodeByID[edge.to]?.title ?? edge.to.rawValue.uuidString,
            "kind": edge.kind.rawValue,
            "label": edge.label,
            "condition": edge.condition,
        ]
    }
}

// MARK: - 子命令

func runImport(_ args: Arguments) -> Int32 {
    guard let input = args.positional.first else {
        return Output.failure(
            "用法：causal import <输入.md> <输出.causal> [--title 标题] [--format storyboard|prose] [--lang 语言]",
            json: args.wantsJSON
        )
    }
    let outputPath = args.positional.count > 1
        ? args.positional[1]
        : input.replacingOccurrences(of: ".md", with: ".causal")
    let inputURL = URL(fileURLWithPath: input)
    let outputURL = URL(fileURLWithPath: outputPath)

    let text: String
    do {
        text = try String(contentsOf: inputURL, encoding: .utf8)
    } catch {
        return Output.failure(CoreText.format("读不到 %@：%@", inputURL.path, error.localizedDescription), json: args.wantsJSON)
    }

    let fallbackTitle = args.values["title"]
        ?? inputURL.deletingPathExtension().lastPathComponent
            .components(separatedBy: "_")
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

    // 未给 --lang 时按表头推断，再退化到 LANG；显式参数优先。
    CLILanguage.install(explicit: args.values["lang"], text: text)

    let forcedMode: MarkdownImport.Mode?
    if let raw = args.values["format"] {
        guard let mode = MarkdownImport.Mode(rawValue: raw) else {
            return Output.failure(CoreText.format("未知格式：%@（可用 storyboard / prose）", raw), json: args.wantsJSON)
        }
        forcedMode = mode
    } else {
        forcedMode = nil
    }

    do {
        let result = try MarkdownImport.makeProject(
            fromMarkdown: text,
            title: fallbackTitle,
            forcedMode: forcedMode
        )
        let project = result.project
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        let report = try ProjectPackage.save(project, to: outputURL)

        if args.wantsJSON {
            var payload = summary(project, packageURL: outputURL)
            payload["ok"] = true
            payload["command"] = "import"
            payload["mode"] = result.mode.rawValue
            payload["notes"] = result.notes
            payload["metadataBytes"] = report.metadataByteCount
            Output.json(payload)
        } else {
            let counts = summary(project)["counts"] as? [String: Int] ?? [:]
            print(CoreText.format("已写出 %@（%@）", outputURL.path, result.mode.rawValue))
            print(CoreText.format("章节 %lld · 卡 %lld · 灵感 %lld", counts["chapters"] ?? 0, counts["cards"] ?? 0, counts["ideas"] ?? 0)
                + CoreText.format(" · 因果 %lld · 人物 %lld · 地点 %lld · 设定 %lld",
                                  counts["edges"] ?? 0, counts["characters"] ?? 0,
                                  counts["places"] ?? 0, counts["settings"] ?? 0))
            for note in result.notes {
                print("  · \(note)")
            }
            for warning in ProjectValidator.issues(in: project).prefix(8) {
                print("  · \(warning)")
            }
        }
        return 0
    } catch {
        return Output.failure(CoreText.format("导入失败：%@", "\(error)"), json: args.wantsJSON)
    }
}

func loadPackage(_ args: Arguments, command: String) -> (LoadedProject, URL)? {
    guard let path = args.positional.first else {
        _ = Output.failure("用法：causal \(command) <工程包.causal>", json: args.wantsJSON)
        return nil
    }
    let url = URL(fileURLWithPath: path)
    do {
        return (try ProjectPackage.load(from: url), url)
    } catch {
        _ = Output.failure(CoreText.format("打不开 %@：%@", url.path, "\(error)"), json: args.wantsJSON)
        return nil
    }
}

func runInfo(_ args: Arguments) -> Int32 {
    guard let (loaded, url) = loadPackage(args, command: "info") else { return 1 }
    let project = loaded.project

    if args.wantsJSON {
        var payload = summary(project, packageURL: url)
        payload["ok"] = true
        payload["command"] = "info"
        payload["cards"] = cardDetail(project)
        payload["edges"] = edgesDetail(project)
        payload["loadWarnings"] = loaded.warnings
        Output.json(payload)
        return 0
    }

    let counts = summary(project)["counts"] as? [String: Int] ?? [:]
    print("\(project.title)")
    if !project.logline.isEmpty { print(project.logline) }
    print(CoreText.format("章节 %lld · 卡 %lld · 灵感 %lld", counts["chapters"] ?? 0, counts["cards"] ?? 0, counts["ideas"] ?? 0)
        + CoreText.format(" · 因果 %lld · 人物 %lld · 地点 %lld · 设定 %lld",
                          counts["edges"] ?? 0, counts["characters"] ?? 0,
                          counts["places"] ?? 0, counts["settings"] ?? 0))
    for chapter in project.chapters {
        print(CoreText.format("【%@】 %lld 张", chapter.title, chapter.order.count))
        for nodeID in chapter.order {
            guard let node = project.node(nodeID) else { continue }
            print("  · \(node.title) — \(node.summary)")
        }
    }
    let ideas = project.nodes.filter { $0.status == .idea }
    if !ideas.isEmpty {
        print(CoreText.format("灵感卡 %lld：", ideas.count))
        for idea in ideas { print("  · \(idea.title)") }
    }
    return 0
}

func runValidate(_ args: Arguments) -> Int32 {
    guard let (loaded, url) = loadPackage(args, command: "validate") else { return 1 }
    let warnings = ProjectValidator.issues(in: loaded.project)
    if args.wantsJSON {
        Output.json([
            "ok": warnings.isEmpty,
            "command": "validate",
            "package": url.path,
            "warnings": warnings,
            "loadWarnings": loaded.warnings,
        ])
    } else if warnings.isEmpty {
        print(CoreText.text("没有问题"))
    } else {
        for warning in warnings { print("· \(warning)") }
    }
    return warnings.isEmpty ? 0 : 1
}

func runOutline(_ args: Arguments) -> Int32 {
    guard let (loaded, url) = loadPackage(args, command: "outline") else { return 1 }
    let project = loaded.project

    // --to 只看通往某个结局的路径
    var route: StoryRoute?
    if let target = args.values["to"] {
        guard let ending = project.nodes.first(where: { $0.title == target || $0.id.rawValue.uuidString == target }) else {
            return Output.failure(CoreText.format("找不到结局「%@」", target), json: args.wantsJSON)
        }
        route = StoryRoute.paths(to: ending.id, in: project)
    }
    if args.wantsJSON {
        let index = project.makeIndex()
        let outlines = OutlineBuilder.build(project: project, index: index, nodes: route?.nodeIDs)
        let payload: [[String: Any]] = outlines.map { outline in
            [
                "chapter": outline.chapterTitle,
                "scenes": outline.sceneCount,
                "revisits": outline.revisitCount,
                "crossChapter": outline.crossChapterCount,
                "detached": outline.detachedCount,
                "rows": outline.rows.map { row in
                    [
                        "title": row.nodeTitle,
                        "indent": row.indent,
                        "role": row.role == .scene ? "scene" : (row.role == .revisit ? "revisit" : "crossChapter"),
                        "incoming": row.incoming?.displayText ?? "",
                    ]
                },
            ]
        }
        Output.json(["ok": true, "command": "outline", "package": url.path, "outlines": payload])
        return 0
    }
    let markdown = route.map { OutlineMarkdown.render(project: project, route: $0) }
        ?? OutlineMarkdown.render(project: project)
    print(markdown, terminator: markdown.hasSuffix("\n") ? "" : "\n")
    return 0
}

func usage() {
    print("""
    causal — 因果的命令行接口与 MCP 服务器

    用法：
      causal import <输入.md> [输出.causal] [--title 标题] [--format storyboard|prose] [--lang zh-Hans|en|ja|zh-Hant] [--json]
      causal info <工程包.causal> [--json]
      causal validate <工程包.causal> [--json]
      causal outline <工程包.causal> [--to 结局] [--json]
      causal apply <工程包.causal> [--ops ops.json | --stdin] [--dry-run] [--json]
      causal export <工程包.causal> [--out 文件]
      causal contract <导出.json> [--json]
      causal audit <工程包.causal> [--json] [--all]
      causal play <工程包.causal> [--choices 1,1] [--out 试读稿.md] [--json]
      causal thread <工程包.causal> [--json]
      causal branch <工程包.causal> [--to 结局] [--mode segments|per-path] [--json]
      causal reach <工程包.causal> --from <卡片> [--json]
      causal bench [工程包.causal] [--json]
      causal history <工程包.causal> [--json]
      causal undo <工程包.causal> [--steps 1] [--json]
      causal redo <工程包.causal> [--steps 1] [--json]
      causal mcp [--package 工程包.causal] [--transport stdio|http] [--host 127.0.0.1] [--port 8765]
          MCP 服务器；默认 stdio。HTTP 需要 CAUSAL_MCP_TOKEN 或 --token / --token-file
      causal mcp-config [--command 可执行文件路径]
          打印通用 MCP 配置（mcpServers 片段），任何支持 command/args 的客户端都能用

    约定：
      · --lang 可放在子命令前后：zh-Hans | en | ja | zh-Hant；缺省按 LANG 前缀推断。
      · 每条命令成功返回 0，失败返回 1，用法错误返回 2。
      · --json 时输出单个 JSON 对象，字段见 docs/cli.md。
    """)
}

// MARK: - 入口

let extraction = Arguments.splittingLanguage(Array(CommandLine.arguments.dropFirst()))
let raw = extraction.arguments
guard let command = raw.first else {
    usage()
    exit(2)
}
var args = Arguments(Array(raw.dropFirst()))
// 子命令前写下的 --lang 注入到统一参数表；命令自身的输出跟随同一套词条。
if let language = extraction.language, args.values["lang"] == nil {
    args.values["lang"] = language
}
CLILanguage.install(explicit: args.values["lang"])
switch command {
case "import":
    exit(runImport(args))
case "info":
    exit(runInfo(args))
case "validate":
    exit(runValidate(args))
case "outline":
    exit(runOutline(args))
case "apply":
    exit(runApply(args))
case "export":
    exit(runExport(args))
case "contract":
    exit(runContract(args))
case "audit":
    exit(runAudit(args))
case "play":
    exit(runPlay(args))
case "thread":
    exit(runThread(args))
case "history":
    exit(runHistory(args))
case "undo":
    exit(runUndo(args))
case "redo":
    exit(runRedo(args))
case "branch":
    exit(runBranch(args))
case "reach":
    exit(runReach(args))
case "bench":
    exit(runBench(args))
case "mcp-config":
    exit(runMCPConfig(args))
case "mcp":
    let transport = args.values["transport"] ?? (args.flags.contains("http") ? "http" : "stdio")
    guard transport == "stdio" || transport == "http" else {
        FileHandle.standardError.write(Data("未知传输：\(transport)（可用 stdio / http）\n".utf8))
        exit(2)
    }
    guard let port = UInt16(args.values["port"] ?? "8765") else {
        FileHandle.standardError.write(Data("端口不正确：\(args.values["port"] ?? "")\n".utf8))
        exit(2)
    }
    var token = args.values["token"]
    if token == nil, let path = args.values["token-file"] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            FileHandle.standardError.write(Data("读不到 token 文件：\(path)\n".utf8))
            exit(2)
        }
        token = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if token == nil {
        token = ProcessInfo.processInfo.environment["CAUSAL_MCP_TOKEN"]
    }
    exit(runMCPServer(
        packagePath: args.values["package"] ?? args.positional.first,
        transport: transport,
        host: args.values["host"] ?? "127.0.0.1",
        port: port,
        token: token
    ))
case "-h", "--help", "help":
    usage()
    exit(0)
default:
    usage()
    exit(2)
}
