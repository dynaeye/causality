import Foundation
import CausalityCore

/// `causal apply <工程包> [--ops 文件] [--stdin] [--dry-run] [--json]`
func runApply(_ args: Arguments) -> Int32 {
    guard let path = args.positional.first else {
        return Output.failure(CoreText.text("用法：causal apply <工程包.causal> [--ops ops.json] [--stdin] [--dry-run]"), json: args.wantsJSON)
    }
    let url = URL(fileURLWithPath: path)

    let opsData: Data
    if let file = args.values["ops"] {
        guard let data = FileManager.default.contents(atPath: file) else {
            return Output.failure(CoreText.format("读不到 %@", file), json: args.wantsJSON)
        }
        opsData = data
    } else if args.flags.contains("stdin") {
        opsData = FileHandle.standardInput.readDataToEndOfFile()
    } else {
        return Output.failure(CoreText.text("要 --ops <文件> 或 --stdin 给一份操作脚本"), json: args.wantsJSON)
    }

    let script: OperationScript
    do {
        script = try JSONDecoder().decode(OperationScript.self, from: opsData)
    } catch {
        return Output.failure(CoreText.format("操作脚本解析失败：%@", "\(error)"), json: args.wantsJSON)
    }

    var project: StoryProject
    do {
        project = try ProjectPackage.load(from: url).project
    } catch {
        return Output.failure(CoreText.format("打不开 %@：%@", url.path, "\(error)"), json: args.wantsJSON)
    }

    let before = project
    let results: [ScriptResult]
    do {
        results = try OperationRunner.apply(script, to: &project)
    } catch {
        return Output.failure("\(error)", json: args.wantsJSON)
    }

    let warnings = ProjectValidator.issues(in: project)
    let dryRun = args.flags.contains("dry-run")
    var written = false
    if !dryRun, project != before {
        do {
            _ = try? ProjectHistory.snapshotCurrent(in: url)
            _ = try ProjectPackage.save(project, to: url)
            written = true
        } catch {
            return Output.failure(CoreText.format("保存失败：%@", "\(error)"), json: args.wantsJSON)
        }
    }

    if args.wantsJSON {
        Output.json([
            "ok": true,
            "command": "apply",
            "package": url.path,
            "dryRun": dryRun,
            "written": written,
            "results": results.map { result -> [String: Any] in
                var item: [String: Any] = [
                    "index": result.index,
                    "op": result.op,
                    "detail": result.detail,
                ]
                if let created = result.createdID { item["createdID"] = created }
                return item
            },
            "counts": summary(project)["counts"] as? [String: Int] ?? [:],
            "warnings": warnings,
        ])
    } else {
        for result in results {
            print("\(result.index + 1). \(result.detail)" + (result.createdID.map { " [\($0)]" } ?? ""))
        }
        print(dryRun ? CoreText.text("演练完成，未写盘")
              : (written ? CoreText.format("已保存 %@", url.path)
                         : CoreText.text("内容没有变化，未写盘")))
        for warning in warnings.prefix(8) { print("  · \(warning)") }
    }
    return 0
}

/// `causal export <工程包> [--out 文件] [--json]`
func runExport(_ args: Arguments) -> Int32 {
    guard let path = args.positional.first else {
        return Output.failure(CoreText.text("用法：causal export <工程包.causal> [--out 文件]"), json: args.wantsJSON)
    }
    let url = URL(fileURLWithPath: path)
    let loaded: LoadedProject
    do {
        loaded = try ProjectPackage.load(from: url)
    } catch {
        return Output.failure(CoreText.format("打不开 %@：%@", url.path, "\(error)"), json: args.wantsJSON)
    }

    let data: Data
    do {
        data = try ProjectCoding.encode(loaded.project)
    } catch {
        return Output.failure(CoreText.format("编码失败：%@", "\(error)"), json: args.wantsJSON)
    }

    let missing = ProjectContract.missingFields(in: data)
    if !missing.isEmpty {
        return Output.failure(
            "导出契约不完整，缺少字段：\n" + missing.map { "  · \($0)" }.joined(separator: "\n"),
            json: args.wantsJSON
        )
    }

    if let out = args.values["out"] {
        do {
            try data.write(to: URL(fileURLWithPath: out))
        } catch {
            return Output.failure(CoreText.format("写出 %@ 失败：%@", out, "\(error)"), json: args.wantsJSON)
        }
        if args.wantsJSON {
            Output.json(["ok": true, "command": "export", "package": url.path, "out": out, "bytes": data.count])
        } else {
            print(CoreText.format("已写出 %@（%lld 字节）", out, data.count))
        }
        return 0
    }

    print(String(decoding: data, as: UTF8.self))
    return 0
}


/// `causal history <工程包> [--json]`
func runHistory(_ args: Arguments) -> Int32 {
    guard let path = args.positional.first else {
        return Output.failure(CoreText.text("用法：causal history <工程包.causal> [--json]"), json: args.wantsJSON)
    }
    let url = URL(fileURLWithPath: path)
    let entries: [SnapshotEntry]
    do {
        entries = try ProjectHistory.list(in: url)
    } catch {
        return Output.failure(CoreText.format("读不到历史：%@", "\(error)"), json: args.wantsJSON)
    }

    if args.wantsJSON {
        Output.json([
            "ok": true,
            "command": "history",
            "package": url.path,
            "count": entries.count,
            "snapshots": entries.map { entry -> [String: Any] in
                [
                    "id": entry.id,
                    "title": entry.title,
                    "revision": entry.revision,
                    "savedAt": ISO8601DateFormatter().string(from: entry.savedAt),
                    "bytes": entry.byteCount,
                ]
            },
        ])
        return 0
    }
    if entries.isEmpty {
        print(CoreText.text("还没有快照"))
        return 0
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd HH:mm:ss"
    for (index, entry) in entries.enumerated() {
        let marker = index == 0 ? CoreText.text("最新") : "    "
        print(CoreText.format("%@ %@  r%lld  %lld 字节  %@",
                              marker, entry.id, entry.revision, entry.byteCount,
                              formatter.string(from: entry.savedAt)))
    }
    return 0
}

/// `causal undo <工程包> [--steps N] [--json]`
func runUndo(_ args: Arguments) -> Int32 {
    guard let path = args.positional.first else {
        return Output.failure(CoreText.text("用法：causal undo <工程包.causal> [--steps 1]"), json: args.wantsJSON)
    }
    let url = URL(fileURLWithPath: path)
    let steps = Int(args.values["steps"] ?? "1") ?? 1

    let restored: [SnapshotEntry]
    do {
        restored = try ProjectHistory.undo(steps: steps, in: url)
    } catch {
        return Output.failure(CoreText.format("回退失败：%@", "\(error)"), json: args.wantsJSON)
    }

    if restored.isEmpty {
        return Output.failure(CoreText.text("没有可撤回的快照"), json: args.wantsJSON)
    }

    if args.wantsJSON {
        Output.json([
            "ok": true,
            "command": "undo",
            "package": url.path,
            "restored": restored.map { ["id": $0.id, "revision": $0.revision, "title": $0.title] },
            "remaining": (try? ProjectHistory.list(in: url).count) ?? 0,
        ])
    } else {
        for entry in restored { print(CoreText.format("回退到 %@（r%lld）", entry.id, entry.revision)) }
    }
    return 0
}


/// `causal contract <导出.json> [--json]`
/// 校验一份导出文件是否满足当前 schemaVersion 的必填字段契约。
func runContract(_ args: Arguments) -> Int32 {
    guard let path = args.positional.first else {
        return Output.failure(CoreText.text("用法：causal contract <导出.json> [--json]"), json: args.wantsJSON)
    }
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else {
        return Output.failure(CoreText.format("读不到 %@", url.path), json: args.wantsJSON)
    }
    let missing = ProjectContract.missingFields(in: data)
    guard missing.isEmpty else {
        if args.wantsJSON {
            Output.json([
                "ok": false,
                "command": "contract",
                "file": url.path,
                "missing": missing,
            ])
        } else {
            print(CoreText.text("缺少字段："))
            for field in missing { print("  · \(field)") }
        }
        return 1
    }
    if args.wantsJSON {
        Output.json(["ok": true, "command": "contract", "file": url.path])
    } else {
        print(CoreText.format("契约通过：%@", url.lastPathComponent))
    }
    return 0
}

/// `causal redo <工程包> [--steps 1] [--json]`
func runRedo(_ args: Arguments) -> Int32 {
    guard let path = args.positional.first else {
        return Output.failure(CoreText.text("用法：causal redo <工程包.causal> [--steps 1]"), json: args.wantsJSON)
    }
    let url = URL(fileURLWithPath: path)
    let steps = Int(args.values["steps"] ?? "1") ?? 1
    let redone: [SnapshotEntry]
    do {
        redone = try ProjectHistory.redo(steps: steps, in: url)
    } catch {
        return Output.failure(CoreText.format("重做失败：%@", "\(error)"), json: args.wantsJSON)
    }
    guard !redone.isEmpty else {
        return Output.failure(CoreText.text("没有可重做的快照"), json: args.wantsJSON)
    }
    if args.wantsJSON {
        Output.json([
            "ok": true,
            "command": "redo",
            "package": url.path,
            "redone": redone.map { ["id": $0.id, "revision": $0.revision, "title": $0.title] },
            "remaining": (try? ProjectHistory.redoList(in: url).count) ?? 0,
        ])
    } else {
        for entry in redone { print(CoreText.format("重做到 %@（r%lld）", entry.id, entry.revision)) }
    }
    return 0
}
