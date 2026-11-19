import Foundation
import CausalityCore

/// `causal thread <工程包> [--json]`
func runThread(_ args: Arguments) -> Int32 {
    guard let path = args.positional.first else {
        return Output.failure("用法：causal thread <工程包.causal> [--json]", json: args.wantsJSON)
    }
    let url = URL(fileURLWithPath: path)
    let loaded: LoadedProject
    do {
        loaded = try ProjectPackage.load(from: url)
    } catch {
        return Output.failure(CoreText.format("打不开 %@：%@", url.path, "\(error)"), json: args.wantsJSON)
    }
    let project = loaded.project
    if args.wantsJSON {
        Output.json([
            "ok": true,
            "command": "thread",
            "package": url.path,
            "threads": project.threads.map { thread -> [String: Any] in
                let points = ThreadSpine.points(for: thread, in: project)
                return [
                    "name": thread.name,
                    "kind": thread.kind.rawValue,
                    "unpaid": thread.isUnpaid,
                    "points": points.map { point in
                        [
                            "role": point.entry.role.rawValue,
                            "chapter": point.chapterTitle,
                            "node": point.node.title,
                            "text": point.entry.text,
                        ]
                    },
                ]
            },
        ])
        return 0
    }
    if project.threads.isEmpty {
        print(CoreText.text("还没有线索。"))
        return 0
    }
    for thread in project.threads {
        let mark = thread.isUnpaid ? CoreText.text("（未收）") : ""
        print(CoreText.format("%@ · %@%@", CoreText.text(thread.kind.displayName), thread.name, mark))
        for point in ThreadSpine.points(for: thread, in: project) {
            let text = point.entry.text.isEmpty ? "" : "　\(point.entry.text)"
            print(CoreText.format("  %@：%@ · %@%@",
                                  CoreText.text(point.entry.role.displayName),
                                  point.chapterTitle, point.node.title, text))
        }
    }
    return 0
}
