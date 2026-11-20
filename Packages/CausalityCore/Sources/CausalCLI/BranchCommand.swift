import Foundation
import CausalityCore

/// `causal branch <工程包> [--to 结局] [--mode segments|per-path] [--json]`
///
/// 不给 `--to` 时列出所有结局与路上卡数。
func runBranch(_ args: Arguments) -> Int32 {
    guard let (loaded, url) = loadPackage(args, command: "branch") else { return 1 }
    let project = loaded.project
    let endings = BranchSynopsis.endings(in: project)
    let mode = BranchSynopsis.Mode(rawValue: args.values["mode"] ?? "segments") ?? .segments

    if let target = args.values["to"] {
        guard let ending = project.nodes.first(where: {
            $0.title == target || $0.id.rawValue.uuidString == target
        }) else {
            return Output.failure(CoreText.format("找不到结局「%@」", target), json: args.wantsJSON)
        }
        let synopsis = BranchSynopsis.make(project: project, endingID: ending.id, mode: mode)
        if args.wantsJSON {
            Output.json([
                "ok": true,
                "command": "branch",
                "package": url.path,
                "ending": synopsis.endingTitle,
                "cardCount": synopsis.cardCount,
                "truncated": synopsis.truncated,
                "blocks": synopsis.blocks.map { block -> [String: Any] in
                    [
                        "label": block.label,
                        "text": block.text,
                        "sentences": block.sentences,
                        "cards": block.nodeIDs.map(\.rawValue.uuidString),
                        "cardCount": block.cardCount,
                        "omitted": block.omitted,
                    ]
                },
            ])
            return 0
        }

        print(CoreText.format("结局 · %@　　%lld 张卡", synopsis.endingTitle, synopsis.cardCount)
            + (synopsis.truncated ? CoreText.text("　（分支太多，只按分叉分块）") : ""))
        if synopsis.blocks.isEmpty {
            print(CoreText.text("这条结局还没有可枚举的路径。"))
            return 0
        }
        let width = synopsis.blocks.map { displayWidth($0.label) }.max() ?? 4
        for block in synopsis.blocks {
            let pad = String(repeating: " ", count: max(2, width - displayWidth(block.label) + 2))
            print("\(block.label)\(pad)\(block.text)")
        }
        return 0
    }

    if args.wantsJSON {
        Output.json([
            "ok": true,
            "command": "branch",
            "package": url.path,
            "endings": endings.map { ["id": $0.id.rawValue.uuidString, "title": $0.title, "cards": $0.cardCount] },
        ])
        return 0
    }
    if endings.isEmpty {
        print(CoreText.text("还没有结局。标一张卡为结局之后，这里会按结局列出分支。"))
        return 0
    }
    for ending in endings {
        print(CoreText.format("结局「%@」　%lld 张卡", ending.title, ending.cardCount))
    }
    return 0
}

/// `causal reach <工程包> --from <卡片> [--json]`
func runReach(_ args: Arguments) -> Int32 {
    guard let (loaded, url) = loadPackage(args, command: "reach") else { return 1 }
    let project = loaded.project
    guard let ref = args.values["from"] ?? args.positional.first else {
        return Output.failure(CoreText.text("用法：causal reach <工程包> --from <卡片标题或 UUID>"), json: args.wantsJSON)
    }
    guard let node = project.nodes.first(where: { $0.title == ref || $0.id.rawValue.uuidString == ref }) else {
        return Output.failure(CoreText.format("找不到卡片「%@」", ref), json: args.wantsJSON)
    }

    let endings = EndingReach.from(node.id, in: project)
    if args.wantsJSON {
        Output.json([
            "ok": true,
            "command": "reach",
            "package": url.path,
            "from": node.title,
            "endings": endings.map { ending -> [String: Any] in
                [
                    "id": ending.endingID.rawValue.uuidString,
                    "title": ending.title,
                    "steps": ending.steps,
                    "mainline": ending.onMainline,
                ]
            },
        ])
        return 0
    }
    if endings.isEmpty {
        print(CoreText.format("「%@」之后走不到任何结局。", node.title))
        return 0
    }
    print(CoreText.format("从「%@」出发：", node.title))
    for ending in endings {
        let mark = ending.onMainline ? CoreText.text("主线") : CoreText.text("支线")
        print(CoreText.format("  · %@　%lld 步　%@", ending.title, ending.steps, mark))
    }
    return 0
}

/// 中文字符在终端里占两格，对齐用。
private func displayWidth(_ text: String) -> Int {
    text.reduce(0) { total, character in
        total + (character.unicodeScalars.first.map { $0.value > 0x2000 ? 2 : 1 } ?? 1)
    }
}
