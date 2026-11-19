import Foundation
import CausalityCore

/// `causal play <工程包> [--choices 1,1] [--out 试读稿.md] [--json]`
func runPlay(_ args: Arguments) -> Int32 {
    guard let path = args.positional.first else {
        return Output.failure("用法：causal play <工程包.causal> [--choices 1,1] [--out 试读稿.md] [--json]", json: args.wantsJSON)
    }
    let url = URL(fileURLWithPath: path)
    let loaded: LoadedProject
    do {
        loaded = try ProjectPackage.load(from: url)
    } catch {
        return Output.failure(CoreText.format("打不开 %@：%@", url.path, "\(error)"), json: args.wantsJSON)
    }
    let project = loaded.project
    guard var play = PlaythroughEngine.start(in: project) else {
        return Output.failure(CoreText.text("没有可试玩的正式场景"), json: args.wantsJSON)
    }

    let choices = (args.values["choices"] ?? "")
        .split(separator: ",")
        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    var choiceIndex = 0
    var error: String?

    while !play.finished, !play.deadEnd, let current = play.current, !current.options.isEmpty {
        let edgeID: EdgeID
        if current.options.count == 1 {
            edgeID = current.options[0].edgeID
        } else {
            guard choiceIndex < choices.count else { break }
            let index = choices[choiceIndex] - 1
            choiceIndex += 1
            guard current.options.indices.contains(index) else {
                error = "第 \(choices[choiceIndex - 1]) 个选项超出范围：这一步只有 \(current.options.count) 个"
                break
            }
            edgeID = current.options[index].edgeID
        }
        guard let next = PlaythroughEngine.choose(edgeID, in: play, project: project) else {
            error = "这一步走不下去"
            break
        }
        play = next
    }

    if let out = args.values["out"] {
        let markdown = PlaythroughMarkdown.render(play, project: project)
        do {
            try markdown.write(to: URL(fileURLWithPath: out), atomically: true, encoding: .utf8)
        } catch {
            return Output.failure(CoreText.format("写出 %@ 失败：%@", out, "\(error)"), json: args.wantsJSON)
        }
    }

    if args.wantsJSON {
        Output.json([
            "ok": error == nil,
            "command": "play",
            "package": url.path,
            "finished": play.finished,
            "deadEnd": play.deadEnd,
            "steps": play.stepCount,
            "words": play.cumulativeWords,
            "error": error ?? "",
            "path": play.steps.map { step -> [String: Any] in
                [
                    "index": step.stepNumber,
                    "title": step.node.title,
                    "chapter": step.node.chapterID.flatMap { project.chapter($0)?.title } ?? "未分章",
                    "words": WordCount.count(of: step.node),
                    "cumulativeWords": step.cumulativeWords,
                    "via": step.incomingLabel ?? "",
                    "options": step.options.map { option in
                        ["label": option.label, "target": option.targetTitle, "condition": option.condition]
                    },
                ]
            },
        ])
    } else {
        for step in play.steps {
            print(CoreText.format("%lld. %@　+%lld 字（累计 %lld）",
                                  step.stepNumber, step.node.title,
                                  WordCount.count(of: step.node), step.cumulativeWords))
            if let label = step.incomingLabel, !label.isEmpty {
                print(CoreText.format("   ← %@", label))
            }
        }
        if let error {
            print(CoreText.format("走不下去：%@", "\(error)"))
        } else if play.finished {
            print(CoreText.format("到达结局。共 %lld 步，%lld 字。", play.stepCount, play.cumulativeWords))
        } else if play.deadEnd {
            print(CoreText.text("这里断了：没有去向，也不是结局。"))
        } else if let current = play.current {
            print(CoreText.text("可选去向："))
            for (index, option) in current.options.enumerated() {
                print(CoreText.format("  %lld. %@ → %@", index + 1, option.label, option.targetTitle))
            }
        }
    }

    if error != nil || play.deadEnd { return 1 }
    return 0
}
