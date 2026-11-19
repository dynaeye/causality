import Foundation
import CausalityCore

/// 最小 MCP 服务器：stdio + 换行分隔的 JSON-RPC 2.0。
///
/// 覆盖读写全流程：打开/保存工程、读全量 JSON、跑编辑脚本、读大纲与校验结果。
/// 工具名与参数见 docs/cli.md。
struct MCPState {
    var project: StoryProject?
    var url: URL?
    /// apply_ops / import_markdown 只改内存；这里标着还没 save_project。
    var dirty = false
    /// open_project / save_project 时的版本指纹；磁盘变了就拒绝覆盖。
    var stamp: PackageStamp?
}

final class MCPServer: @unchecked Sendable {
    private var state = MCPState()
    private let version = "0.1.0"
    /// 请求串行执行；stdin 的读线程只负责收通知和取消，不被长 apply 卡住。
    private let requestQueue = DispatchQueue(label: "causal.mcp.requests")
    private let outputLock = NSLock()
    private let sinkLock = NSLock()
    /// HTTP 传输时，一次请求的输出临时接到这里；stdio 保持 nil。
    private var currentSink: (@Sendable (Data) -> Void)?
    private let cancelLock = NSLock()
    private var cancelledRequests: Set<String> = []

    init(packagePath: String?) {
        if let packagePath {
            let url = URL(fileURLWithPath: packagePath)
            do {
                state.project = try ProjectPackage.load(from: url).project
                state.url = url
            } catch {
                log(CoreText.format("打不开 %@：%@", url.path, "\(error)"))
            }
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data(("[causal] " + message + "\n").utf8))
    }

    func run() {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // JSON-RPC 2.0：解析失败回 -32700，id 为 null。
                send([
                    "jsonrpc": "2.0",
                    "id": NSNull(),
                    "error": ["code": -32700, "message": "Parse error"],
                ])
                continue
            }

            let method = message["method"] as? String ?? ""
            if method == "notifications/cancelled" {
                let params = message["params"] as? [String: Any] ?? [:]
                cancel(requestID: params["requestId"])
                continue
            }
            if method.hasPrefix("notifications/") { continue }

            requestQueue.async { [self] in
                process(data)
            }
        }
        // 等还在跑的请求收尾，再让进程退出。
        requestQueue.sync {}
    }

    /// HTTP 传输用：在会话自己的请求队列上执行，输出走 emit，完成时回调。
    func handleRequest(
        _ data: Data,
        emit: @escaping @Sendable (Data) -> Void,
        completion: @escaping @Sendable () -> Void
    ) {
        requestQueue.async { [self] in
            sinkLock.lock()
            let previous = currentSink
            currentSink = emit
            sinkLock.unlock()
            defer {
                sinkLock.lock()
                currentSink = previous
                sinkLock.unlock()
                completion()
            }
            process(data)
        }
    }

    /// 取消通知不进请求队列：长 apply 正在跑时也要立刻置位。
    func cancel(requestID: Any?) {
        guard let key = requestKey(requestID) else { return }
        cancelLock.lock()
        cancelledRequests.insert(key)
        cancelLock.unlock()
    }

    private func process(_ data: Data) {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // JSON-RPC 2.0：解析失败回 -32700，id 为 null。
            send([
                "jsonrpc": "2.0",
                "id": NSNull(),
                "error": ["code": -32700, "message": "Parse error"],
            ])
            return
        }
        let method = message["method"] as? String ?? ""
        if method == "notifications/cancelled" {
            let params = message["params"] as? [String: Any] ?? [:]
            cancel(requestID: params["requestId"])
            return
        }
        if method.hasPrefix("notifications/") { return }
        handle(message)
    }

    // MARK: - 分发

    private func handle(_ message: [String: Any]) {
        let method = message["method"] as? String ?? ""
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]

        if id == nil {
            // 通知，不需要回。
            return
        }

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? "2024-11-05"
            reply(id: id, result: [
                "protocolVersion": requested,
                "capabilities": [
                    "tools": ["listChanged": false],
                    "resources": ["subscribe": false, "listChanged": false],
                    "prompts": ["listChanged": false],
                ],
                "serverInfo": ["name": "causal", "version": version],
            ])
        case "ping":
            reply(id: id, result: [String: Any]())
        case "tools/list":
            reply(id: id, result: ["tools": tools()])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let progressToken = (params["_meta"] as? [String: Any])?["progressToken"]
                ?? params["progressToken"]
            callTool(name, arguments: arguments, id: id, progressToken: progressToken)
        case "resources/list":
            reply(id: id, result: ["resources": resources()])
        case "resources/read":
            let uri = params["uri"] as? String ?? ""
            guard let content = readResource(uri) else {
                error(id: id, code: -32602, message: CoreText.format("找不到资源：%@", uri))
                return
            }
            reply(id: id, result: ["contents": [[
                "uri": uri,
                "mimeType": content.mimeType,
                "text": content.text,
            ]]])
        case "prompts/list":
            reply(id: id, result: ["prompts": prompts()])
        case "prompts/get":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: String] ?? [:]
            guard let result = prompt(name: name, arguments: arguments) else {
                error(id: id, code: -32602, message: CoreText.format("找不到提示词：%@", name))
                return
            }
            reply(id: id, result: result)
        default:
            error(id: id, code: -32601, message: CoreText.format("不支持的方法：%@", method))
        }
    }

    // MARK: - 工具

    private func tools() -> [[String: Any]] {
        [
            tool(
                "open_project",
                CoreText.text("打开一个 .causal 工程包，后续工具都作用在它上面"),
                ["path": .init(type: "string", description: CoreText.text("工程包路径"))],
                required: ["path"]
            ),
            tool(
                "save_project",
                CoreText.text("把当前项目写回磁盘（唯一落盘点）；给了 path 就另存"),
                ["path": .init(type: "string", description: CoreText.text("另存位置，可省"))],
                required: []
            ),
            tool("project_info", CoreText.text("当前项目的摘要：章节、计数、校验提示"), [:], required: []),
            tool("project_export", CoreText.text("当前项目的完整 JSON（与 project.json 同构）"), [:], required: []),
            tool("list_chapters", CoreText.text("列出章节与卡数"), [:], required: []),
            tool("list_cards", CoreText.text("列出卡片；可按章节过滤"), [
                "chapter": .init(type: "string", description: CoreText.text("章节标题或 UUID，可省")),
            ], required: []),
            tool("get_card", CoreText.text("读一张卡的全文与引用"), [
                "card": .init(type: "string", description: CoreText.text("卡片标题或 UUID")),
            ], required: ["card"]),
            tool("list_entities", CoreText.text("列出人物、地点或设定"), [
                "kind": .init(
                    type: "string",
                    description: CoreText.text("类别"),
                    enumValues: ["character", "place", "setting"]
                ),
            ], required: ["kind"]),
            tool(
                "apply_ops",
                CoreText.format(
                    "按顺序执行一批编辑操作，只改内存；调用 save_project 才落盘。ops 是对象数组，每项形如 %@；完整 op 表见 docs/cli.md",
                    "{\"op\":\"updateCard\",\"card\":\"" + CoreText.text("卡名") + "\",\"summary\":\"…\"}"
                ),
                [
                    "ops": .init(
                        type: "array",
                        description: CoreText.text("操作对象数组，每项含 op 与对应参数"),
                        itemsType: "object"
                    ),
                    "dryRun": .init(type: "boolean", description: CoreText.text("只演算不落盘，可省")),
                ],
                required: ["ops"]
            ),
            tool(
                "import_markdown",
                CoreText.text(
                    "把 Markdown 读成新项目：故事板表格或普通 ## 章 / ### 场 / 段落（替换当前项目，记得 save_project）"
                ),
                [
                    "path": .init(type: "string", description: CoreText.text("markdown 文件路径")),
                    "markdown": .init(type: "string", description: CoreText.text("也可以直接给正文")),
                    "title": .init(type: "string", description: CoreText.text("项目名，可省")),
                ],
                required: []
            ),
            tool("history", CoreText.text("列出工程包里的历史快照（新的在前）"), [:], required: []),
            tool("undo", CoreText.text("把最近一份快照写回；steps 可撤回多步"), [
                "steps": .init(type: "integer", description: CoreText.text("撤回几步，默认 1")),
            ], required: []),
            tool("redo", CoreText.text("把撤回过的状态重做回来；steps 可重做多步"), [
                "steps": .init(type: "integer", description: CoreText.text("重做几步，默认 1")),
            ], required: []),
            tool("validate", CoreText.text("跑模型层校验"), [:], required: []),
            tool("outline", CoreText.text("读推导出的大纲；给 to 就只看通往那个结局的路径"), [
                "format": .init(
                    type: "string",
                    description: CoreText.text("默认 markdown"),
                    enumValues: ["markdown", "json"]
                ),
                "to": .init(type: "string", description: CoreText.text("结局的标题或 UUID，可省")),
            ], required: []),
        ]
    }

    struct Property {
        var type: String
        var description: String
        var enumValues: [String]?
        var itemsType: String?

        init(type: String, description: String, enumValues: [String]? = nil, itemsType: String? = nil) {
            self.type = type
            self.description = description
            self.enumValues = enumValues
            self.itemsType = itemsType
        }
    }

    private func tool(_ name: String, _ description: String, _ properties: [String: Property], required: [String]) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": [:], "additionalProperties": false]
        var props: [String: Any] = [:]
        for (key, value) in properties {
            var item: [String: Any] = ["type": value.type, "description": value.description]
            if let enumValues = value.enumValues {
                item["enum"] = enumValues
                item["type"] = value.type
            }
            if value.type == "array", let itemsType = value.itemsType {
                item["items"] = ["type": itemsType]
            }
            props[key] = item
        }
        schema["properties"] = props
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": description, "inputSchema": schema]
    }

    // MARK: - resources / prompts

    private struct ResourceContent {
        var mimeType: String
        var text: String
    }

    /// 工程包里的可浏览对象：整个项目、大纲、每张卡、每章、每个人物。
    private func resources() -> [[String: Any]] {
        guard let project = state.project else { return [] }
        let index = project.makeIndex()
        var items: [[String: Any]] = [
            [
                "uri": "causal://project",
                "name": CoreText.text("工程摘要"),
                "mimeType": "application/json",
                "description": CoreText.text("整个 project.json 的快照"),
            ],
            [
                "uri": "causal://outline",
                "name": CoreText.text("大纲"),
                "mimeType": "text/markdown",
                "description": OutlineMarkdown.render(project: project).count > 0
                    ? CoreText.text("与导出同一份推导")
                    : CoreText.text("空大纲"),
            ],
        ]
        for node in project.nodes {
            items.append([
                "uri": "causal://card/\(node.id.rawValue.uuidString)",
                "name": node.title.isEmpty ? CoreText.text("未命名卡") : node.title,
                "mimeType": "text/markdown",
                "description": "\(CoreText.text(node.status.displayName)) · \(CoreText.text(node.kind.displayName))",
            ])
        }
        for chapter in project.chapters {
            items.append([
                "uri": "causal://chapter/\(chapter.id.rawValue.uuidString)",
                "name": chapter.title,
                "mimeType": "text/markdown",
                "description": CoreText.format("%lld 张卡", index.nodes(in: chapter.id).count),
            ])
        }
        for character in project.characters {
            items.append([
                "uri": "causal://character/\(character.id.rawValue.uuidString)",
                "name": character.name.isEmpty ? CoreText.text("未命名人物") : character.name,
                "mimeType": "text/markdown",
                "description": CoreText.text("人物资料与出场"),
            ])
        }
        return items
    }

    private func readResource(_ uri: String) -> ResourceContent? {
        guard let project = state.project else { return nil }
        let index = project.makeIndex()
        if uri == "causal://project" {
            guard let data = try? ProjectCoding.encode(project) else { return nil }
            return ResourceContent(mimeType: "application/json", text: String(decoding: data, as: UTF8.self))
        }
        if uri == "causal://outline" {
            return ResourceContent(mimeType: "text/markdown", text: OutlineMarkdown.render(project: project))
        }
        if uri.hasPrefix("causal://card/"),
           let id = UUID(uuidString: String(uri.dropFirst("causal://card/".count))),
           let node = index.nodeByID[NodeID(rawValue: id)] {
            return ResourceContent(mimeType: "text/markdown", text: cardMarkdown(node, project: project, index: index))
        }
        if uri.hasPrefix("causal://chapter/"),
           let id = UUID(uuidString: String(uri.dropFirst("causal://chapter/".count))),
           let chapter = project.chapter(ChapterID(rawValue: id)) {
            var lines = ["# \(chapter.title)"]
            if !chapter.summary.isEmpty { lines += ["", chapter.summary] }
            let nodes = index.nodes(in: chapter.id)
            lines += ["", CoreText.format("%lld 张卡：", nodes.count)]
            for node in nodes {
                let detail = node.summary.isEmpty
                    ? node.title
                    : CoreText.format("%@：%@", node.title, node.summary)
                lines.append("- \(detail)")
            }
            return ResourceContent(mimeType: "text/markdown", text: lines.joined(separator: "\n"))
        }
        if uri.hasPrefix("causal://character/"),
           let id = UUID(uuidString: String(uri.dropFirst("causal://character/".count))),
           let character = project.characters.first(where: { $0.id == CharacterID(rawValue: id) }) {
            return ResourceContent(mimeType: "text/markdown", text: characterMarkdown(character, project: project, index: index))
        }
        return nil
    }

    private func cardMarkdown(_ node: StoryNode, project: StoryProject, index: ProjectIndex) -> String {
        var lines = [
            "# \(node.title)",
            "",
            "\(CoreText.text(node.status.displayName)) · \(CoreText.text(node.kind.displayName))",
        ]
        if let chapterID = node.chapterID, let chapter = project.chapter(chapterID) {
            lines.append(CoreText.format("章节：%@", chapter.title))
        }
        if !node.summary.isEmpty { lines += ["", CoreText.format("摘要：%@", node.summary)] }
        if !node.body.isEmpty { lines += ["", CoreText.text("正文："), node.body] }
        let separator = CoreText.text("、")
        let characters = node.characterIDs.compactMap { index.characterByID[$0]?.name }
        if !characters.isEmpty {
            lines += ["", CoreText.text("出场：") + characters.joined(separator: separator)]
        }
        let places = node.placeIDs.compactMap { index.placeByID[$0]?.name }
        if !places.isEmpty { lines.append(CoreText.text("地点：") + places.joined(separator: separator)) }
        let settings = project.settings
            .filter { node.settingIDs.contains($0.id) || $0.attachedNodeIDs.contains(node.id) }
            .map(\.title)
        if !settings.isEmpty {
            lines.append(CoreText.text("事实设定：") + settings.joined(separator: separator))
        }
        let outgoing = index.outgoingEdges(of: node.id)
        if !outgoing.isEmpty {
            lines += ["", CoreText.text("去向：")]
            for edge in outgoing {
                let target = index.nodeByID[edge.to]?.title ?? CoreText.text("未知")
                let label = edge.label.isEmpty ? CoreText.text(edge.kind.displayName) : edge.label
                lines.append("- \(label) → \(target)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func characterMarkdown(
        _ character: StoryCharacter,
        project: StoryProject,
        index: ProjectIndex
    ) -> String {
        var lines = ["# \(character.name.isEmpty ? CoreText.text("未命名人物") : character.name)"]
        if !character.summary.isEmpty { lines += ["", CoreText.format("简介：%@", character.summary)] }
        if !character.notes.isEmpty { lines.append(CoreText.format("备注：%@", character.notes)) }
        let scenes = project.nodes.filter {
            $0.status == .draft && $0.characterIDs.contains(character.id)
        }
        lines += ["", CoreText.format("出场 %lld 场：", scenes.count)]
        for node in scenes {
            let chapter = node.chapterID.flatMap { project.chapter($0)?.title }
                ?? CoreText.text("未分章")
            lines.append("- \(chapter) · \(node.title)")
        }
        let relations = character.relations.compactMap { relation -> String? in
            guard let other = index.characterByID[relation.target]?.name else { return nil }
            return "- " + CoreText.format("%@：%@", CoreText.text(relation.kind.displayName), other)
        }
        if !relations.isEmpty {
            lines += ["", CoreText.text("亲属与亲友：")] + relations
        }
        let graph = CharacterGraph.build(project: project)
        let coPresence = graph.coPresenceLinks.filter {
            $0.from == character.id || $0.to == character.id
        }
        if !coPresence.isEmpty {
            lines += ["", CoreText.text("同场：")]
            for link in coPresence {
                let otherID = link.from == character.id ? link.to : link.from
                let other = index.characterByID[otherID]?.name ?? "?"
                lines.append(CoreText.format("- %@ × %lld 场", other, link.weight))
            }
        }
        return lines.joined(separator: "\n")
    }
    private func prompts() -> [[String: Any]] {
        [
            [
                "name": "polish-card",
                "title": CoreText.text("润色这一场"),
                "description": CoreText.text("保持事实、人物与顺序，把选中场景的正文改得更含蓄。"),
                "arguments": [
                    ["name": "card", "description": CoreText.text("卡片标题或 UUID"), "required": true],
                    ["name": "note", "description": CoreText.text("改写方向，可省"), "required": false],
                ],
            ],
            [
                "name": "find-broken",
                "title": CoreText.text("找断头与伪选择"),
                "description": CoreText.text("跑一遍结构体检，把问题翻译成可执行的修法。"),
                "arguments": [],
            ],
            [
                "name": "add-causality",
                "title": CoreText.text("补一条因果"),
                "description": CoreText.text("给两张卡写一条因果连线与选项文字，产出 apply_ops 可用的改动。"),
                "arguments": [
                    ["name": "from", "description": CoreText.text("起点卡片标题或 UUID"), "required": true],
                    ["name": "to", "description": CoreText.text("终点卡片标题或 UUID"), "required": true],
                    ["name": "kind", "description": "cause / choice / condition / plain", "required": false],
                ],
            ],
        ]
    }

    private func prompt(name: String, arguments: [String: String]) -> [String: Any]? {
        guard let project = state.project else { return nil }
        let index = project.makeIndex()

        func resolveCard(_ raw: String?) -> StoryNode? {
            guard let raw, !raw.isEmpty else { return nil }
            return project.nodes.first {
                $0.id.rawValue.uuidString == raw || $0.title == raw
            }
        }

        let text: String
        switch name {
        case "polish-card":
            guard let card = resolveCard(arguments["card"]) else { return nil }
            let note = arguments["note"].flatMap { $0.isEmpty ? nil : $0 }
                ?? CoreText.text("更含蓄，保留原意与人物")
            text = [
                CoreText.format("请润色「%@」这一场。要求：%@。", card.title, note),
                CoreText.text("保持事实、人物与顺序不变；不新增原文没有的情节；只输出改写后的正文。"),
                "",
                CoreText.text("场景："),
                cardMarkdown(card, project: project, index: index),
            ].joined(separator: "\n")
        case "find-broken":
            let findings = NarrativeAudit.run(project: project)
            let list = findings.map {
                CoreText.format(
                    "- [%@] %@ %@：%@",
                    CoreText.text($0.severity.displayName), $0.rule, $0.title, $0.message
                )
            }
            text = [
                CoreText.format("这是《%@》的结构体检结果。请逐条给出可执行的修法，", project.title),
                CoreText.text("每条写明改哪张卡、加/删哪条连线；不要改正文。"),
                "",
                list.isEmpty ? CoreText.text("体检没有报错。") : list.joined(separator: "\n"),
            ].joined(separator: "\n")
        case "add-causality":
            guard let from = resolveCard(arguments["from"]), let to = resolveCard(arguments["to"]) else {
                return nil
            }
            let kind = arguments["kind"] ?? "cause"
            text = [
                CoreText.format("请为「%@」→「%@」写一条 %@ 连线。", from.title, to.title, kind),
                CoreText.text("给出 label（选项原文/原因）与可选的 condition，并说明理由。"),
                CoreText.format("用 apply_ops 的格式给出改动：%@。", #"{"ops":[{"op":"connect", ...}]}"#),
                "",
                CoreText.text("起点："),
                cardMarkdown(from, project: project, index: index),
                CoreText.text("终点："),
                cardMarkdown(to, project: project, index: index),
            ].joined(separator: "\n")
        default:
            return nil
        }
        return [
            "description": name,
            "messages": [[
                "role": "user",
                "content": ["type": "text", "text": text],
            ]],
        ]
    }

    private func callTool(
        _ name: String,
        arguments: [String: Any],
        id: Any?,
        progressToken: Any?
    ) {
        let key = requestKey(id)
        if let key, isCancelled(key) {
            error(id: id, code: -32800, message: CoreText.text("请求已取消"))
            clearCancelled(key)
            return
        }
        defer {
            if let key { clearCancelled(key) }
        }
        do {
            let text = try dispatch(
                name,
                arguments: arguments,
                requestKey: key,
                progressToken: progressToken
            )
            reply(id: id, result: [
                "content": [["type": "text", "text": text]],
                "isError": false,
            ])
        } catch {
            reply(id: id, result: [
                "content": [["type": "text", "text": "\(error)"]],
                "isError": true,
            ])
        }
    }

    // MARK: - 取消与进度

    private func requestKey(_ id: Any?) -> String? {
        guard let id else { return nil }
        if let number = id as? NSNumber { return "i:\(number.intValue)" }
        if let value = id as? Int { return "i:\(value)" }
        if let value = id as? String { return "s:\(value)" }
        return "x:\(String(describing: id))"
    }

    private func isCancelled(_ key: String) -> Bool {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        return cancelledRequests.contains(key)
    }

    private func clearCancelled(_ key: String) {
        cancelLock.lock()
        cancelledRequests.remove(key)
        cancelLock.unlock()
    }

    private func sendProgress(_ token: Any, progress: Int, total: Int) {
        send([
            "jsonrpc": "2.0",
            "method": "notifications/progress",
            "params": [
                "progressToken": token,
                "progress": progress,
                "total": total,
                "message": CoreText.format("已应用 %lld/%lld 条", progress, total),
            ],
        ])
    }

    // MARK: - 工具实现

    private func dispatch(
        _ name: String,
        arguments: [String: Any],
        requestKey: String?,
        progressToken: Any?
    ) throws -> String {
        if let text = try projectTool(name, arguments: arguments) { return text }
        if let text = try contentTool(name, arguments: arguments) { return text }
        if let text = try editTool(
            name,
            arguments: arguments,
            requestKey: requestKey,
            progressToken: progressToken
        ) { return text }
        throw ToolError.message(CoreText.format("没有这个工具：%@", name))
    }

    private func projectTool(_ name: String, arguments: [String: Any]) throws -> String? {
        switch name {
        case "open_project":
            let path = try string(arguments, "path")
            let url = URL(fileURLWithPath: path)
            let loaded = try ProjectPackage.load(from: url)
            state.project = loaded.project
            state.url = url
            state.dirty = false
            state.stamp = ProjectPackage.stamp(in: url)
            return jsonText(summary(loaded.project, packageURL: url))
        case "save_project":
            guard var project = state.project else { throw ToolError.noProject }
            // 时间戳要在写盘之前改，磁盘与内存才是同一份。
            project.modifiedAt = Timestamp.now()
            if let path = arguments["path"] as? String {
                let url = URL(fileURLWithPath: path)
                _ = try? ProjectHistory.snapshotCurrent(in: url)
                _ = try ProjectPackage.save(project, to: url)
                state.url = url
            } else if let url = state.url {
                do {
                    _ = try? ProjectHistory.snapshotCurrent(in: url)
                    _ = try ProjectPackage.save(project, to: url, expecting: state.stamp)
                } catch let PackageError.conflict(expected, current) {
                    throw ToolError.message(
                        CoreText.format(
                            "工程包已被其它程序改动（%@）。先 open_project 重新载入；要把内存里的改动留下，就 save_project 到新的 path。",
                            expected.conflictDetail(with: current)
                        )
                    )
                }
            } else {
                throw ToolError.message(CoreText.text("当前项目还没有落过盘，save_project 要给 path"))
            }
            state.project = project
            state.dirty = false
            state.stamp = state.url.flatMap { ProjectPackage.stamp(in: $0) }
            return jsonText([
                "ok": true,
                "package": state.url?.path ?? "",
                "revision": project.revision,
                "dirty": false,
            ])
        case "project_info":
            var payload = summary(try requireProject(), packageURL: state.url)
            payload["dirty"] = state.dirty
            if let stamp = state.stamp {
                payload["openedStamp"] = [
                    "revision": stamp.revision,
                    "fileModifiedAt": stamp.fileModifiedAt?.timeIntervalSince1970 ?? -1,
                ]
            }
            if let url = state.url, let disk = ProjectPackage.stamp(in: url) {
                payload["diskStamp"] = [
                    "revision": disk.revision,
                    "fileModifiedAt": disk.fileModifiedAt?.timeIntervalSince1970 ?? -1,
                ]
            }
            return jsonText(payload)
        case "project_export":
            let data = try ProjectCoding.encode(try requireProject())
            return String(decoding: data, as: UTF8.self)
        case "history":
            let project = try requireProject()
            let entries = (try? state.url.map { try ProjectHistory.list(in: $0) }) ?? nil
            return jsonText([
                "package": state.url?.path ?? "",
                "snapshots": (entries ?? []).map { entry -> [String: Any] in
                    [
                        "id": entry.id,
                        "title": entry.title,
                        "revision": entry.revision,
                        "savedAt": ISO8601DateFormatter().string(from: entry.savedAt),
                        "bytes": entry.byteCount,
                    ]
                },
                "revision": project.revision,
            ])
        case "undo":
            guard let url = state.url else {
                throw ToolError.message(CoreText.text("当前项目还没落过盘，没有历史可撤"))
            }
            let steps = arguments["steps"] as? Int ?? 1
            let restored = try ProjectHistory.undo(steps: steps, in: url)
            guard !restored.isEmpty else { throw ToolError.message(CoreText.text("没有可撤回的快照")) }
            state.project = try ProjectPackage.load(from: url).project
            state.stamp = ProjectPackage.stamp(in: url)
            state.dirty = false
            let project = try requireProject()
            return jsonText([
                "ok": true,
                "restored": restored.map { ["id": $0.id, "revision": $0.revision, "title": $0.title] },
                "counts": summary(project)["counts"] as? [String: Int] ?? [:],
            ])
        case "redo":
            guard let url = state.url else {
                throw ToolError.message(CoreText.text("当前项目还没落过盘，没有历史可重做"))
            }
            let steps = arguments["steps"] as? Int ?? 1
            let redone = try ProjectHistory.redo(steps: steps, in: url)
            guard !redone.isEmpty else { throw ToolError.message(CoreText.text("没有可重做的快照")) }
            state.project = try ProjectPackage.load(from: url).project
            state.stamp = ProjectPackage.stamp(in: url)
            state.dirty = false
            let project = try requireProject()
            return jsonText([
                "ok": true,
                "redone": redone.map { ["id": $0.id, "revision": $0.revision, "title": $0.title] },
                "counts": summary(project)["counts"] as? [String: Int] ?? [:],
            ])
        case "validate":
            let issues = ProjectValidator.issues(in: try requireProject())
            return jsonText(["ok": issues.isEmpty, "warnings": issues])
        default:
            return nil
        }
    }

    private func contentTool(_ name: String, arguments: [String: Any]) throws -> String? {
        switch name {
        case "list_chapters":
            let project = try requireProject()
            return jsonText(project.chapters.map { ["id": $0.id.rawValue.uuidString, "title": $0.title, "cards": $0.order.count] })
        case "list_cards":
            let project = try requireProject()
            let index = project.makeIndex()
            var cards = cardDetail(project)
            if let chapterRef = arguments["chapter"] as? String, !chapterRef.isEmpty {
                guard let chapter = project.chapters.first(where: {
                    $0.id.rawValue.uuidString == chapterRef || $0.title == chapterRef
                }) else {
                    throw ToolError.message(CoreText.format("找不到章节「%@」", chapterRef))
                }
                cards = cards.filter { ($0["chapter"] as? String) == chapter.title }
            }
            _ = index
            return jsonText(cards)
        case "get_card":
            let project = try requireProject()
            let ref = try string(arguments, "card")
            let node = project.nodes.first { $0.title == ref || $0.id.rawValue.uuidString == ref }
            guard let node else { throw ToolError.message(CoreText.format("找不到卡片「%@」", ref)) }
            let detail = cardDetail(project).first { ($0["id"] as? String) == node.id.rawValue.uuidString } ?? [:]
            return jsonText(detail)
        case "list_entities":
            let project = try requireProject()
            switch try string(arguments, "kind") {
            case "character":
                return jsonText(project.characters.map {
                    ["id": $0.id.rawValue.uuidString, "name": $0.name, "summary": $0.summary]
                })
            case "place":
                return jsonText(project.places.map {
                    ["id": $0.id.rawValue.uuidString, "name": $0.name, "summary": $0.summary]
                })
            case "setting":
                return jsonText(project.settings.map {
                    ["id": $0.id.rawValue.uuidString, "title": $0.title, "confirmed": $0.isConfirmed, "locked": $0.isLocked]
                })
            default:
                throw ToolError.message(CoreText.text("kind 只能是 character / place / setting"))
            }
        case "outline":
            let project = try requireProject()
            let format = arguments["format"] as? String ?? "markdown"
            var route: StoryRoute?
            if let target = arguments["to"] as? String, !target.isEmpty {
                guard let ending = project.nodes.first(where: {
                    $0.title == target || $0.id.rawValue.uuidString == target
                }) else {
                    throw ToolError.message(CoreText.format("找不到结局「%@」", target))
                }
                route = StoryRoute.paths(to: ending.id, in: project)
            }
            if format == "json" {
                let index = project.makeIndex()
                let payload: [[String: Any]] = OutlineBuilder.build(
                    project: project, index: index, nodes: route?.nodeIDs
                ).map { outline in
                    [
                        "chapter": outline.chapterTitle,
                        "scenes": outline.sceneCount,
                        "rows": outline.rows.map { row in
                            ["title": row.nodeTitle, "indent": row.indent,
                             "incoming": row.incoming?.displayText ?? ""]
                        },
                    ]
                }
                return jsonText(payload)
            }
            return route.map { OutlineMarkdown.render(project: project, route: $0) }
                ?? OutlineMarkdown.render(project: project)
        default:
            return nil
        }
    }

    private func editTool(
        _ name: String,
        arguments: [String: Any],
        requestKey: String?,
        progressToken: Any?
    ) throws -> String? {
        switch name {
        case "apply_ops":
            let project = try requireProject()
            guard let rawOps = arguments["ops"] else { throw ToolError.message(CoreText.text("缺少 ops")) }
            let payload: [String: Any] = ["version": 1, "ops": rawOps]
            let data = try JSONSerialization.data(withJSONObject: payload)
            let script: OperationScript
            do {
                script = try JSONDecoder().decode(OperationScript.self, from: data)
            } catch {
                throw ToolError.message(CoreText.format("操作脚本解析失败：%@", "\(error)"))
            }
            let dryRun = arguments["dryRun"] as? Bool ?? false
            let total = script.ops.count
            let chunkSize = 20
            var working = project
            var results: [ScriptResult] = []
            var start = 0
            while start < total {
                if let requestKey, isCancelled(requestKey) {
                    throw ToolError.message(
                        CoreText.format("请求已取消：完成 %lld/%lld 条，内存与磁盘都未改动", start, total)
                    )
                }
                let end = min(start + chunkSize, total)
                let chunk = OperationScript(
                    version: script.version,
                    ops: Array(script.ops[start..<end])
                )
                do {
                    let chunkResults = try OperationRunner.apply(chunk, to: &working)
                    results.append(contentsOf: chunkResults.map { result in
                        var adjusted = result
                        adjusted.index = result.index + start
                        return adjusted
                    })
                } catch let error as ScriptError {
                    throw ScriptError(index: error.index + start, op: error.op, reason: error.reason)
                }
                start = end
                if let progressToken {
                    sendProgress(progressToken, progress: start, total: total)
                }
            }
            if !dryRun {
                state.project = working
                state.dirty = true
            }
            return jsonText([
                "ok": true,
                "dryRun": dryRun,
                "dirty": state.dirty,
                "hint": dryRun ? "" : CoreText.text("改动只在内存里，调用 save_project 落盘"),
                "results": results.map { result -> [String: Any] in
                    var item: [String: Any] = ["index": result.index, "op": result.op, "detail": result.detail]
                    if let created = result.createdID { item["createdID"] = created }
                    return item
                },
                "counts": summary(working)["counts"] as? [String: Int] ?? [:],
            ])
        case "import_markdown":
            let text: String
            var title = arguments["title"] as? String
            if let path = arguments["path"] as? String, !path.isEmpty {
                let url = URL(fileURLWithPath: path)
                text = try String(contentsOf: url, encoding: .utf8)
                if title == nil {
                    title = url.deletingPathExtension().lastPathComponent
                        .components(separatedBy: "_").filter { !$0.isEmpty }.joined(separator: " · ")
                }
            } else if let markdown = arguments["markdown"] as? String, !markdown.isEmpty {
                text = markdown
            } else {
                throw ToolError.message(CoreText.text("要给 path 或 markdown"))
            }
            let project = try StoryboardMarkdown.makeProject(fromMarkdown: text, title: title ?? "")
            state.project = project
            state.url = nil
            state.dirty = true
            var payload = summary(project)
            payload["dirty"] = true
            return jsonText(payload)
        default:
            return nil
        }
    }
    // MARK: - 小工具

    private func requireProject() throws -> StoryProject {
        guard let project = state.project else { throw ToolError.noProject }
        return project
    }

    private func string(_ arguments: [String: Any], _ key: String) throws -> String {
        guard let value = arguments[key] as? String, !value.isEmpty else {
            throw ToolError.message(CoreText.format("缺少 %@", key))
        }
        return value
    }

    private func jsonText(_ value: Any) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - JSON-RPC

    private func reply(id: Any?, result: Any) {
        send(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    private func error(id: Any?, code: Int, message: String) {
        send(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])
    }

    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
        sinkLock.lock()
        let sink = currentSink
        sinkLock.unlock()
        if let sink {
            sink(data)
            return
        }
        outputLock.lock()
        defer { outputLock.unlock() }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

enum ToolError: Error, CustomStringConvertible {
    case noProject
    case message(String)

    var description: String {
        switch self {
        case .noProject: CoreText.text("还没有打开项目，先调 open_project 或 import_markdown")
        case let .message(text): text
        }
    }
}

func runMCPServer(
    packagePath: String?,
    transport: String = "stdio",
    host: String = "127.0.0.1",
    port: UInt16 = 8765,
    token: String? = nil
) -> Int32 {
    switch transport {
    case "stdio":
        let server = MCPServer(packagePath: packagePath)
        server.run()
        return 0
    case "http":
        guard let token, !token.isEmpty else {
            FileHandle.standardError.write(Data(
                (CoreText.text("HTTP 传输需要 token：设置 CAUSAL_MCP_TOKEN，或传 --token / --token-file") + "\n").utf8
            ))
            return 2
        }
        let server = MCPHTTPServer(
            options: MCPHTTPOptions(host: host, port: port, token: token),
            packagePath: packagePath
        )
        return server.run()
    default:
        let message = CoreText.format("未知传输：%@（可用 stdio / http）", transport)
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 2
    }
}
