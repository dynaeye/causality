import Foundation
import CausalityCore

/// `causal audit <工程包> [--json] [--all]`
func runAudit(_ args: Arguments) -> Int32 {
    guard let path = args.positional.first else {
        return Output.failure("用法：causal audit <工程包.causal> [--json] [--all]", json: args.wantsJSON)
    }
    let url = URL(fileURLWithPath: path)
    let loaded: LoadedProject
    do {
        loaded = try ProjectPackage.load(from: url)
    } catch {
        return Output.failure(CoreText.format("打不开 %@：%@", url.path, "\(error)"), json: args.wantsJSON)
    }

    let includeWaived = args.flags.contains("all")
    let findings = NarrativeAudit.run(project: loaded.project, includeWaived: includeWaived)
    let waivedCount = NarrativeAudit.waivedFindings(in: loaded.project).count
    let errors = findings.filter { $0.severity == .error }.count
    let warnings = findings.filter { $0.severity == .warning }.count
    let infos = findings.filter { $0.severity == .info }.count

    if args.wantsJSON {
        let payload: [String: Any] = [
            "ok": errors == 0,
            "command": "audit",
            "package": url.path,
            "counts": ["error": errors, "warning": warnings, "info": infos],
            "waived": waivedCount,
            "findings": findings.map { finding in
                var row: [String: Any] = [
                    "rule": finding.rule,
                    "severity": finding.severity.rawValue,
                    "title": finding.title,
                    "message": finding.message,
                    "subject": finding.subjectID,
                ]
                if let nodeID = finding.nodeID {
                    row["nodeID"] = nodeID.rawValue.uuidString
                }
                return row
            },
        ]
        Output.json(payload)
    } else if findings.isEmpty {
        print(CoreText.text("体检通过。"))
    } else {
        for finding in findings {
            print(CoreText.format("[%@] %@ %@", CoreText.text(finding.severity.displayName), finding.rule, finding.title))
            print("  \(finding.message)")
        }
        print(CoreText.format("共 %lld 个错误 · %lld 个警告 · %lld 个提示（已忽略 %lld 条）", errors, warnings, infos, waivedCount))
    }
    return errors == 0 ? 0 : 1
}
