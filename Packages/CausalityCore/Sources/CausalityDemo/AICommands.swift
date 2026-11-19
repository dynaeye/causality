import Foundation
import CausalityCore

// MARK: - 凭据

func credential(for provider: AIProvider) -> AICredential? {
    let envNames: [String]
    switch provider.id {
    case "openai":
        envNames = ["CAUSAL_OPENAI_KEY", "OPENAI_API_KEY"]
    case "opencode-go":
        envNames = ["CAUSAL_OPENCODE_KEY", "OPENCODE_API_KEY"]
    case "deepseek":
        envNames = ["CAUSAL_DEEPSEEK_KEY", "DEEPSEEK_API_KEY"]
    case "minimax-cn":
        envNames = ["CAUSAL_MINIMAX_KEY", "MINIMAX_API_KEY"]
    default:
        envNames = []
    }
    for name in envNames {
        if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty {
            return AICredential(apiKey: value, sessionID: "cs-cli-\(provider.id)")
        }
    }
    if let stored = AICredentialStore.load(providerID: provider.id), !stored.isEmpty {
        return AICredential(apiKey: stored, sessionID: "cs-cli-\(provider.id)")
    }
    return nil
}

// MARK: - 固定样例提案（模拟通过）

/// 用固定样例把「校验 → 采纳 → 撤销」走一遍，不需要网络。
func runProposalDemo() -> Int32 {
    let script = ConvergenceDemo.make()
    let project = script.project
    let scope = ProposalScope.selection(nodeID: script.askTownsfolk, in: project)
    let arrivalEdge = project.edges.first { $0.from == script.askTownsfolk && $0.to == script.ending }

    print("== 固定样例：把公开追问改成更含蓄的相遇 ==")
    print("范围：选中「赶集的人认出纸张」及相邻，可改节点 \(scope.editableNodeIDs.count) 个")

    guard let arrivalEdge else {
        print("样本缺少到达结局的连线")
        return 1
    }

    let payload = ProposalPayload(
        summary: "保留众人送信的结局，把公开追问改成更含蓄的相遇",
        changes: [
            ProposalChange(
                target: .node,
                id: script.askTownsfolk.rawValue.uuidString,
                body: "卖纸的老人没有招呼，只把同纹的纸推到阿禾手边。赶集的人看见了，各自收摊。"
            ),
            ProposalChange(
                target: .edge,
                id: arrivalEdge.id.rawValue.uuidString,
                label: "众人沉默地跟着阿禾往渡口走"
            ),
            ProposalChange(
                target: .setting,
                id: project.settings.first?.id.rawValue.uuidString ?? "",
                text: "母亲的债不是钱，是一句没送到的话。"
            ),
        ],
        notes: ["守密分支与另一个结局未改动。"]
    )

    var nodeRevisions: [NodeID: Int] = [:]
    for nodeID in scope.editableNodeIDs {
        if let node = project.node(nodeID) { nodeRevisions[nodeID] = node.revision }
    }
    let proposal = AIProposal(baseRevision: project.revision, nodeRevisions: nodeRevisions, payload: payload)
    let validated = ProposalValidator.validate(proposal, in: project, scope: scope)

    print("")
    print("— 逐项结果 —")
    for item in validated.items {
        let mark: String
        switch item.outcome {
        case .accept: mark = "采纳"
        case let .reject(reason): mark = "拒绝：\(reason)"
        case let .suggestion(reason): mark = "建议：\(reason)"
        }
        print("  [\(mark)] \(item.action.displayName)：\(item.title)")
        for diff in item.detail {
            print("      \(diff.field)：\(diff.after)")
        }
    }
    print("")
    let tally = "分组 \(validated.groups.count) 组"
        + " · 可采纳 \(validated.acceptedItems.count) 项"
        + " · 拒绝 \(validated.rejectedItems.count) 项"
        + " · 建议 \(validated.suggestionItems.count) 项"
    print(tally)

    guard validated.status == .ready else {
        print("状态异常：\(validated.status)")
        return 1
    }

    var failures: [String] = []
    check(validated.acceptedItems.count == 2, "场景与连线两项可采纳", into: &failures)
    check(validated.suggestionItems.count == 1, "锁定设定的改动只作建议", into: &failures)
    check(validated.acceptedOperations.count == 2, "采纳操作只包含两项", into: &failures)

    // 采纳（这一步要主线程，命令行直接在主线程跑）。
    var adoptSummary = ""
    MainActor.assumeIsolated {
        let editor = StoryEditor(project: project)
        do {
            let count = try editor.adopt(validated)
            adoptSummary = "已采纳 \(count) 项；撤销栈深度 \(editor.undoDepth)"
            check(editor.project.node(script.askTownsfolk)?.body.contains("同纹的纸") == true, "正文已改", into: &failures)
            check(editor.project.node(script.keepSecret) == project.node(script.keepSecret), "另一条分支原样保留", into: &failures)
            let rows = OutlineBuilder.build(project: editor.project).flatMap(\.rows)
            check(rows.filter { $0.nodeID == script.ending && $0.role == .scene }.count == 1, "结局正文仍只有一份", into: &failures)
            check(try editor.undo(), "一次撤销回退整份提案", into: &failures)
            check(editor.project == project, "撤销后与原文逐字段一致", into: &failures)
        } catch {
            failures.append("采纳失败：\(error)")
        }
    }

    print("")
    print(adoptSummary)
    print("")
    if failures.isEmpty {
        print("模拟通过：固定样例的校验、采纳、撤销全部符合预期。")
        return 0
    }
    for failure in failures { print("未通过：\(failure)") }
    return 1
}

// MARK: - 真实联调

func runAIProbe() async -> Int32 {
    var exitCode: Int32 = 0
    for provider in AIProvider.builtIn {
        print("== \(provider.displayName) · \(provider.endpointURL.absoluteString)")
        guard let credential = credential(for: provider) else {
            print("  未验证：没有找到凭据（环境变量或钥匙串）")
            print("")
            continue
        }
        let client = AIClient()
        var models: [String] = []
        do {
            models = try await client.listModels(provider: provider, credential: credential)
        } catch {
            print("  目录读取失败：\(error)")
        }
        if models.isEmpty {
            models = provider.builtInModels
            if models.isEmpty {
                print("  没有目录，也没有内置清单")
            } else {
                print("  目录不可用，内置清单 \(models.count) 个：")
            }
        } else {
            print("  目录 \(models.count) 个：")
        }
        for model in models.prefix(12) { print("    - \(model)") }

        let model = provider.defaultModel
        guard !model.isEmpty else {
            print("  跳过文本请求：没有默认模型")
            print("")
            continue
        }
        let request = AIRequest(
            provider: provider,
            model: model,
            systemPrompt: "你是测试助手，用一句中文回答。",
            userMessage: "说一句「联通正常」。",
            maxOutputTokens: 256,
            sessionID: "causal-probe"
        )
        do {
            let completion = try await client.complete(request, credential: credential)
            let text = completion.text.trimmingCharacters(in: .whitespacesAndNewlines)
            print("  文本请求成功（model=\(completion.model)）：\(text)")
        } catch {
            print("  文本请求失败：\(error)")
            exitCode = 1
        }
        print("")
    }
    return exitCode
}

func runAIRequest(arguments: [String]) async -> Int32 {
    guard arguments.count >= 3 else {
        print("用法：cs-demo ai <provider> <model> <指令>")
        print("provider：openai | opencode-go | deepseek | minimax-cn")
        return 2
    }
    let providerID = arguments[0]
    let model = arguments[1]
    let instruction = arguments.dropFirst(2).joined(separator: " ")

    guard let provider = AIProvider.builtIn.first(where: { $0.id == providerID }) else {
        print("未知服务：\(providerID)")
        return 2
    }
    guard let credential = credential(for: provider) else {
        print("未验证：没有找到 \(provider.displayName) 的凭据")
        return 1
    }

    let script = ConvergenceDemo.make()
    let project = script.project
    // 调试预算用：CAUSAL_MAX_TOKENS=300 可以把触发截断的路径跑一遍。
    let budget = ProcessInfo.processInfo.environment["CAUSAL_MAX_TOKENS"].flatMap(Int.init)
    let request = ProposalRequest(
        kind: .editSelection,
        instruction: instruction,
        contextScope: .selection,
        selection: script.askTownsfolk,
        provider: provider,
        model: model,
        credential: credential,
        maxOutputTokens: budget ?? 8000
    )

    var exitCode: Int32 = 0
    do {
        let service = ProposalService()
        do {
            let result = try await service.run(request, project: project)
            print("模型：\(provider.displayName) / \(model)")
            print("上下文引用：\(result.context.references.count) 项")
            print("")
            print("— 原始回复 —")
            print(result.rawText)
            print("")
            if let validated = result.validated {
                print("— 校验结果（\(validated.status)）—")
                for item in validated.items {
                    let mark: String
                    switch item.outcome {
                    case .accept: mark = "采纳"
                    case let .reject(reason): mark = "拒绝：\(reason)"
                    case let .suggestion(reason): mark = "建议：\(reason)"
                    }
                    print("  [\(mark)] \(item.action.displayName)：\(item.title)")
                }
            } else {
                print("解析失败：\(result.parseFailure ?? "未知原因")")
                exitCode = 1
            }
        } catch {
            print("请求失败：\(error)")
            exitCode = 1
        }
    }
    return exitCode
}

// MARK: - 落地一份示例工程包

/// 把「河灯里的字」写成真实的 .causal 包，方便在 App 里直接打开验收。
func runMakeSample(arguments: [String]) -> Int32 {
    guard let destination = arguments.first else {
        print("用法：cs-demo make-sample <输出目录> [配图路径]")
        return 2
    }
    let script = ConvergenceDemo.make()
    var project = script.project
    let directory = URL(fileURLWithPath: destination, isDirectory: true)
    let packageURL = directory.appendingPathComponent("\(project.title).\(ProjectPackage.fileExtension)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var assetData: [AssetID: Data] = [:]
    if arguments.count >= 2 {
        let imageURL = URL(fileURLWithPath: arguments[1])
        if let data = try? Data(contentsOf: imageURL) {
            let asset = Asset(
                fileName: "sample-cover.png",
                sha256: Digest.sha256Hex(data),
                byteCount: data.count,
                caption: "夜河上的河灯"
            )
            var operations = ProjectMutations.appendAsset(asset, to: project)
            operations += ProjectMutations.attachCover(asset.id, to: script.lantern, in: project)
            try? ProjectEditing.apply(operations, to: &project)
            assetData[asset.id] = data
        } else {
            print("读不到配图：\(imageURL.path)")
        }
    }

    do {
        let report = try ProjectPackage.save(project, to: packageURL, newAssetData: assetData)
        print("已写出：\(packageURL.path)")
        print("节点 \(project.nodes.count) · 章节 \(project.chapters.count) · 配图写入 \(report.writtenAssetIDs.count)")
        return 0
    } catch {
        print("写出失败：\(error)")
        return 1
    }
}
