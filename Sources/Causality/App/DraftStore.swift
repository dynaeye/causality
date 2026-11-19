import Foundation
import CausalityCore

/// 一次草稿写入的结果。缺图照实说，恢复草稿时界面要能讲清楚。
struct DraftWriteReport {
    var url: URL
    var missingAssetFileNames: [String]
}

/// 未命名项目的草稿包。
///
/// 新建的项目还没选位置时也要立刻落盘：写作工具里，崩溃丢稿是最不能接受的一种失败。
/// 草稿就是普通 `.causal` 包，放在 Application Support 下；第一次 ⌘S 时搬到用户选的位置。
enum DraftStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Causality", isDirectory: true)
            .appendingPathComponent("Drafts", isDirectory: true)
    }

    /// 写入过程中的暂存区：先在这里写完整包，再整包换到草稿位置。
    private static var stagingDirectory: URL {
        directory.appendingPathComponent(".staging", isDirectory: true)
    }

    @discardableResult
    static func makeDraft(
        from project: StoryProject,
        newAssetData: [AssetID: Data] = [:],
        copyingAssetsFrom source: URL? = nil
    ) throws -> DraftWriteReport {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeTitle = project.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        let name = safeTitle.isEmpty ? "未命名" : safeTitle
        let url = directory.appendingPathComponent(
            "\(name)-\(project.id.uuidString.prefix(8)).\(ProjectPackage.fileExtension)",
            isDirectory: true
        )

        // 同名草稿可能已经存在：先写到暂存区，写完整了再换。写坏时旧草稿仍然完整。
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let staged = stagingDirectory.appendingPathComponent(
            "\(project.id.uuidString).\(ProjectPackage.fileExtension)",
            isDirectory: true
        )
        try? fileManager.removeItem(at: staged)
        let report: SaveReport
        do {
            // 草稿要带齐两边的图：内存里刚贴的（newAssetData）和原包已存的（source）。
            report = try ProjectPackage.save(
                project,
                to: staged,
                newAssetData: newAssetData,
                copyingAssetsFrom: source
            )
        } catch {
            // 写到一半失败：半成品不能留在暂存区挡住下一次。
            try? fileManager.removeItem(at: staged)
            throw error
        }
        do {
            try ProjectPackage.replacePackage(at: url, with: staged)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
        return DraftWriteReport(
            url: url,
            missingAssetFileNames: report.missingAssetIDs.compactMap { project.asset($0)?.fileName }
        )
    }

    /// 还没被搬走的草稿，按修改时间从新到旧。
    static func drafts() -> [URL] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        return entries
            .filter { ProjectPackage.isProjectPackage($0) }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return left > right
            }
    }

    /// 起始页只留最近 `limit` 份草稿；多出来的移到废纸篓，之后还能找回。
    /// `except` 是当前打开的那份，正在用的包不能动。
    @discardableResult
    static func trim(keeping limit: Int, except openURL: URL? = nil) -> [URL] {
        let all = drafts()
        guard all.count > limit else { return all }
        var kept: [URL] = []
        for url in all {
            if url == openURL || kept.count < limit {
                kept.append(url)
            } else {
                _ = discard(url)
            }
        }
        return kept
    }

    /// 草稿里存的标题，起始页按它显示。
    static func title(of url: URL) -> String {
        guard let data = try? Data(contentsOf: ProjectPackage.metadataURL(in: url)),
              let project = try? ProjectCoding.decode(data) else {
            return url.deletingPathExtension().lastPathComponent
        }
        return project.title
    }

    /// 草稿搬到用户选的位置；搬成功后删掉草稿。
    ///
    /// 目标已有旧工程时先把旧包挪开，整包换成功再进废纸篓。搬失败就把旧包放回原处。
    static func adopt(_ draft: URL, to destination: URL) throws {
        try ProjectPackage.replacePackage(at: destination, with: draft)
    }

    /// 清掉超过保留期的草稿和写了一半的暂存包。启动时跑一次。
    @discardableResult
    static func purge(olderThan days: Int = 30) -> Int {
        let fileManager = FileManager.default
        let deadline = Date().addingTimeInterval(-Double(days) * 86_400)
        let stagingDeadline = Date().addingTimeInterval(-86_400)
        var purged = 0

        // 写完没换成功的暂存包：留一天足够排查，之后可以清掉。
        if let staged = try? fileManager.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            for url in staged {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                guard modified < stagingDeadline else { continue }
                if (try? fileManager.removeItem(at: url)) != nil { purged += 1 }
            }
        }

        // 替换时没能进废纸篓的旧包备份（`*.old`）。
        if let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            for url in entries where url.lastPathComponent.hasSuffix(".old") {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                guard modified < stagingDeadline else { continue }
                if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
                    purged += 1
                }
            }
        }

        for url in drafts() {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            guard modified < deadline else { continue }
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
                purged += 1
            }
        }
        return purged
    }

    /// 把草稿移进废纸篓。失败时返回 false，由界面说明原因。
    @discardableResult
    static func discard(_ draft: URL) -> Bool {
        (try? FileManager.default.trashItem(at: draft, resultingItemURL: nil)) != nil
    }
}
