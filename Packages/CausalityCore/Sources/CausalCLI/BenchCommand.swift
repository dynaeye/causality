import Foundation
import CausalityCore

/// `causal bench [工程包]`：量打开、推导与内存占用。
///
/// 帧率要在 App 里用 Instruments 看，这条命令管的是能用数字说话的那部分。
func runBench(_ args: Arguments) -> Int32 {
    let project: StoryProject
    let packageURL: URL?

    if let path = args.positional.first {
        let url = URL(fileURLWithPath: path)
        do {
            project = try ProjectPackage.load(from: url).project
            packageURL = url
        } catch {
            return Output.failure(CoreText.format("打不开 %@：%@", url.path, "\(error)"), json: args.wantsJSON)
        }
    } else {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-bench-\(UUID().uuidString)", isDirectory: true)
        let url = temp.appendingPathComponent("基准.\(ProjectPackage.fileExtension)", isDirectory: true)
        project = BenchmarkFixture.make()
        do {
            try ProjectPackage.save(project, to: url)
        } catch {
            return Output.failure(CoreText.format("准备基准包失败：%@", "\(error)"), json: args.wantsJSON)
        }
        packageURL = url
    }

    // 打开耗时：取五次的中位数，并拆出解码与校验
    var opens: [Double] = []
    var decodes: [Double] = []
    var validates: [Double] = []
    if let packageURL {
        let metadata = try? Data(contentsOf: ProjectPackage.metadataURL(in: packageURL))
        for _ in 0 ..< 5 {
            let started = DispatchTime.now().uptimeNanoseconds
            _ = try? ProjectPackage.load(from: packageURL)
            opens.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)

            if let metadata {
                let decodeStart = DispatchTime.now().uptimeNanoseconds
                let decoded = try? ProjectCoding.decode(metadata)
                decodes.append(Double(DispatchTime.now().uptimeNanoseconds - decodeStart) / 1_000_000)
                if let decoded {
                    let validateStart = DispatchTime.now().uptimeNanoseconds
                    _ = ProjectValidator.issues(in: decoded)
                    validates.append(Double(DispatchTime.now().uptimeNanoseconds - validateStart) / 1_000_000)
                }
            }
        }
    }
    let openMedian = opens.sorted()[max(0, opens.count / 2)]
    let decodeMedian = decodes.sorted()[max(0, decodes.count / 2)]
    let validateMedian = validates.sorted()[max(0, validates.count / 2)]

    func measure(_ name: String, _ work: () -> Void) -> Double {
        let started = DispatchTime.now().uptimeNanoseconds
        work()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        _ = name
        return ms
    }

    var index = project.makeIndex()
    let indexMs = measure("index") { index = project.makeIndex() }
    let projectIndex = index
    var outlines: [ChapterOutline] = []
    let outlineMs = measure("outline") { outlines = OutlineBuilder.build(project: project, index: index) }
    var mainline = Mainline.empty
    let mainlineMs = measure("mainline") { mainline = Mainline.derive(in: project) }
    let routeMs = measure("route") {
        if let ending = project.nodes.first(where: { $0.kind == .ending }) {
            _ = StoryRoute.paths(to: ending.id, in: project)
        }
    }
    // 故事板一次 body 会取卡上百次：量一次「取卡 524 次」的总成本
    let chapterIDs = project.chapters.map(\.id)
    var taken = 0
    let cardsMs = measure("cards") {
        guard !chapterIDs.isEmpty else { return }
        for step in 0..<524 {
            taken += projectIndex.nodes(in: chapterIDs[step % chapterIDs.count]).count
        }
    }
    var markdown = ""
    let exportMs = measure("export") { markdown = OutlineMarkdown.render(project: project, outlines: outlines) }

    let rss = residentMemoryMB()

    let payload: [String: Any] = [
        "ok": true,
        "command": "bench",
        "package": packageURL?.path ?? "",
        "counts": summary(project)["counts"] as? [String: Int] ?? [:],
        "milliseconds": [
            "openMedian": round(openMedian * 100) / 100,
            "decode": round(decodeMedian * 100) / 100,
            "validate": round(validateMedian * 100) / 100,
            "index": round(indexMs * 100) / 100,
            "outline": round(outlineMs * 100) / 100,
            "mainline": round(mainlineMs * 100) / 100,
            "route": round(routeMs * 100) / 100,
            "markdownExport": round(exportMs * 100) / 100,
            "cards524": round(cardsMs * 100) / 100,
        ],
        "memory": ["residentMB": round(rss * 10) / 10],
        "outlineRows": outlines.reduce(0) { $0 + $1.rows.count },
        "markdownBytes": markdown.utf8.count,
        "mainlineNodes": mainline.nodeIDs.count,
    ]

    if args.wantsJSON {
        Output.json(payload)
    } else {
        let counts = summary(project)["counts"] as? [String: Int] ?? [:]
        print(CoreText.format("规模：节点 %lld · 因果 %lld · 章节 %lld",
                              counts["cards"] ?? 0, counts["edges"] ?? 0, counts["chapters"] ?? 0))
        print(CoreText.format("打开 %.2f ms（五次中位，其中解码 %.2f ms、校验 %.2f ms）",
                              openMedian, decodeMedian, validateMedian))
        print(CoreText.format("索引 %.2f ms · 大纲 %.2f ms · 主线 %.2f ms · 路线 %.2f ms · 导出 %.2f ms",
                              indexMs, outlineMs, mainlineMs, routeMs, exportMs))
        print(CoreText.format("取卡 %lld 次 %.2f ms（%lld 张）", 524, cardsMs, taken))
        print(CoreText.format("常驻内存 %.1f MB", rss))
        print(CoreText.format("大纲行 %lld · Markdown %lld 字节 · 主线 %lld 张卡",
                              outlines.reduce(0) { $0 + $1.rows.count }, markdown.utf8.count,
                              mainline.nodeIDs.count))
    }
    return 0
}

/// 当前进程的常驻内存（MB）。
func residentMemoryMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }
    return Double(info.resident_size) / 1024 / 1024
}
