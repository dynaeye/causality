import Foundation
import CausalityCore

// MARK: - 体检

extension ProjectSession {
    /// 体检按需跑：编辑后防抖 250 ms，放到后台算，界面不等它。
    func refreshAudit() {
        auditTask?.cancel()
        guard let project else {
            auditFindings = []
            auditWaivedFindings = []
            return
        }
        let snapshot = project
        auditTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let all = await Task.detached(priority: .utility) {
                NarrativeAudit.run(project: snapshot, includeWaived: true)
            }.value
            guard !Task.isCancelled else { return }
            let waivedKeys = Set(snapshot.auditWaivers.map(\.waiverKey))
            self?.auditFindings = all.filter { !waivedKeys.contains($0.id) }
            self?.auditWaivedFindings = all.filter { waivedKeys.contains($0.id) }
        }
    }

    func showAudit() {
        guard project != nil else { return }
        isWriting = false
        isAuditing = true
        refreshAudit()
    }

    func closeAudit() {
        isAuditing = false
    }

    /// 工程提示来自三处：校验、导入备注、保存时没落盘的配图。只有用户点「重新体检」才重算，
    /// 免得一边写一边把刚关掉的提醒又拉回来。
    func revalidateWarnings() {
        guard let project else {
            warnings = []
            return
        }
        warnings = ProjectValidator.issues(in: project)
    }

    /// 关掉一条工程提示（只影响这次的列表，重新体检会再算一遍）。
    func dismissWarning(at index: Int) {
        guard warnings.indices.contains(index) else { return }
        warnings.remove(at: index)
    }

    func clearWarnings() {
        warnings = []
    }

    /// 忽略一条问题，理由跟着包走。
    func waive(_ finding: AuditFinding, reason: String) {
        guard let project else { return }
        let waiver = AuditWaiver(
            ruleID: finding.rule,
            subjectID: finding.subjectID,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        apply(ProjectMutations.addAuditWaiver(waiver, to: project), name: InterfaceLanguage.label("忽略体检项"))
    }

    /// 把一条忽略记录撤掉，问题重新出现。
    func restoreWaiver(_ waiver: AuditWaiver) {
        guard let project else { return }
        apply(ProjectMutations.removeAuditWaiver(waiver.id, in: project), name: InterfaceLanguage.label("恢复体检项"))
    }

    func waiver(for finding: AuditFinding) -> AuditWaiver? {
        project?.auditWaivers.first { $0.waiverKey == finding.id }
    }
}
