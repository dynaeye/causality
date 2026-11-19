import Foundation
import CausalityCore

// 命令行演示：不依赖 App，直接跑模型层与保存链路。
// 用法：
//   swift run cs-demo demo
//   swift run cs-demo benchmark

func renderOutline(_ project: StoryProject) -> String {
    let index = project.makeIndex()
    var lines: [String] = []
    for outline in OutlineBuilder.build(project: project, index: index) {
        let summary = [
            "场景 \(outline.sceneCount)",
            "汇合跳转 \(outline.revisitCount)",
            "跨章 \(outline.crossChapterCount)",
            "未接线 \(outline.detachedCount)",
        ].joined(separator: " · ")
        lines.append("【\(outline.chapterTitle)】 " + summary)
        for row in outline.rows {
            let pad = String(repeating: "    ", count: row.indent)
            let title: String
            switch row.role {
            case .scene:
                title = row.nodeTitle + (row.origin == .detached ? "（未接线）" : "")
            case .revisit:
                title = "↪ 回到「\(row.nodeTitle)」"
            case .crossChapter:
                let chapterTitle = row.targetChapterID.flatMap { index.chapterByID[$0]?.title } ?? "另一章"
                title = "→ 转入 \(chapterTitle)「\(row.nodeTitle)」"
            }
            let source = row.incoming.map { "  ← \($0.displayText)" } ?? ""
            lines.append("  \(pad)\(title)\(source)")
        }
    }
    return lines.joined(separator: "\n")
}

func runDemo() -> Int32 {
    print("== 第 1 步：从空项目建两条路，接到同一个结局 ==")
    let script = ConvergenceDemo.make()
    let project = script.project
    let index = project.makeIndex()
    print("节点 \(project.nodes.count) · 发展线 \(project.edges.count) · 章节 \(project.chapters.count)")
    print("")
    print(renderOutline(project))
    print("")

    print("== 第 2 步：保存到 .causal 包 ==")
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("causal-demo-\(UUID().uuidString)", isDirectory: true)
    let packageURL = root.appendingPathComponent("河灯里的字.\(ProjectPackage.fileExtension)", isDirectory: true)
    var failures: [String] = []
    do {
        let report = try ProjectPackage.save(project, to: packageURL)
        let assetSummary = "写入配图 \(report.writtenAssetIDs.count) · 复用 \(report.reusedAssetIDs.count)"
        print("元数据 \(report.metadataByteCount) 字节 · " + assetSummary)
    } catch {
        print("保存失败：\(error)")
        return 1
    }

    print("")
    print("== 第 3 步：重新打开 ==")
    let loaded: LoadedProject
    do {
        loaded = try ProjectPackage.load(from: packageURL)
    } catch {
        print("打开失败：\(error)")
        return 1
    }
    print("警告 \(loaded.warnings.count) 条")
    print("")
    print(renderOutline(loaded.project))
    print("")

    print("== 第 4 步：逐条核对 ==")
    let reopenedIndex = loaded.project.makeIndex()
    let rows = OutlineBuilder.build(project: loaded.project, index: reopenedIndex).flatMap(\.rows)

    let endingSceneRows = rows.filter { $0.nodeID == script.ending && $0.role == .scene }
    let endingRevisitRows = rows.filter { $0.nodeID == script.ending && $0.role == .revisit }
    let labels = rows.compactMap(\.incoming?.label)

    check(endingSceneRows.count == 1, "结局正文只出现一份（实际 \(endingSceneRows.count) 份）", into: &failures)
    check(endingRevisitRows.count == 1, "第二条路以跳转收尾（实际 \(endingRevisitRows.count) 处）", into: &failures)
    check(labels.contains(script.keepSecretLabel), "保留选项「\(script.keepSecretLabel)」", into: &failures)
    check(labels.contains(script.askTownsfolkLabel), "保留选项「\(script.askTownsfolkLabel)」", into: &failures)
    check(labels.contains(script.causeLabel), "保留原因「\(script.causeLabel)」", into: &failures)
    check(loaded.project == project, "保存后重开，工程内容与保存前一致", into: &failures)

    let markdown = OutlineMarkdown.render(project: loaded.project)
    let hasBothOptions = markdown.contains(script.keepSecretLabel)
        && markdown.contains(script.askTownsfolkLabel)
    check(hasBothOptions, "Markdown 导出含两条选项", into: &failures)
    let endingHeadings = markdown.components(separatedBy: "### 旧渡口的信").count - 1
    check(endingHeadings == 1, "Markdown 里结局正文也只有一个标题", into: &failures)

    if failures.isEmpty {
        print("全部通过：\(packageURL.path)")
        return 0
    }
    for failure in failures {
        print("未通过：\(failure)")
    }
    return 1
}

func check(_ condition: Bool, _ message: String, into failures: inout [String]) {
    if condition {
        print("  ✓ \(message)")
    } else {
        failures.append(message)
    }
}

func runBenchmark() -> Int32 {
    print("== 生成基准样本（固定种子 0x5EED5EED）==")
    let started = Date()
    let project = BenchmarkFixture.make()
    let buildMilliseconds = Date().timeIntervalSince(started) * 1000
    let facts = BenchmarkFixture.facts(of: project)
    print(String(format: "构建用时 %.0f ms", buildMilliseconds))
    print("节点 \(facts.nodeCount) · 发展线 \(facts.edgeCount) · 章节 \(facts.chapterCount)")
    let structure = "分支 \(facts.branchNodes) · 汇合 \(facts.mergeNodes) · 回环边 \(facts.cycleEdges)"
    print(structure)
    print("跨章边 \(facts.crossChapterEdges) · 孤立节点 \(facts.orphanNodes)")
    let outlineSummary = [
        "大纲行 \(facts.outlineRowCount)",
        "汇合跳转 \(facts.revisitRows)",
        "跨章跳转 \(facts.crossChapterRows)",
        "未接线 \(facts.detachedRows)",
    ].joined(separator: " · ")
    print(outlineSummary)

    let outlineStarted = Date()
    let outlines = OutlineBuilder.build(project: project)
    let outlineMilliseconds = Date().timeIntervalSince(outlineStarted) * 1000
    print(String(format: "大纲推导用时 %.1f ms（%d 章）", outlineMilliseconds, outlines.count))

    let markdown = OutlineMarkdown.render(project: project, outlines: outlines)
    print("Markdown 导出 \(markdown.count) 字符")

    var failures: [String] = []
    check(facts.nodeCount == 500, "节点数 500", into: &failures)
    check(facts.edgeCount == 800, "发展线 800", into: &failures)
    check(facts.branchNodes > 0, "覆盖分支", into: &failures)
    check(facts.mergeNodes > 0, "覆盖汇合", into: &failures)
    check(facts.cycleEdges > 0, "覆盖回环", into: &failures)
    check(facts.orphanNodes >= 6, "覆盖孤立节点", into: &failures)
    check(facts.crossChapterRows > 0, "覆盖跨章跳转", into: &failures)
    return failures.isEmpty ? 0 : 1
}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "demo"
switch command {
case "demo":
    exit(runDemo())
case "benchmark":
    exit(runBenchmark())
case "make-sample":
    exit(runMakeSample(arguments: Array(arguments.dropFirst())))
case "proposal-demo":
    exit(runProposalDemo())
case "ai-probe":
    exit(await runAIProbe())
case "ai":
    exit(await runAIRequest(arguments: Array(arguments.dropFirst())))
default:
    print("可用命令：demo | benchmark | make-sample <目录> [配图] | proposal-demo | ai-probe | ai <provider> <model> <指令>")
    exit(2)
}
