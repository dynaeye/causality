import Foundation

/// 工程包的历史快照。
///
/// 每次写入前先把当前的 `project.json` 存进包内 `history/`，`undo` 就是把最近一份写回去。
/// 快照只放元数据（图片在 `assets/` 里按内容去重，回退时不需要重写）。
public struct SnapshotEntry: Codable, Sendable, Equatable, Identifiable {
    /// 快照文件名去掉扩展名，恢复时用它定位。
    public var id: String
    public var title: String
    public var revision: Int
    public var savedAt: Date
    public var byteCount: Int

    public init(id: String, title: String, revision: Int, savedAt: Date, byteCount: Int) {
        self.id = id
        self.title = title
        self.revision = revision
        self.savedAt = savedAt
        self.byteCount = byteCount
    }
}

public enum ProjectHistory {
    public static let directoryName = "history"
    /// 一个包最多留多少份快照，超过就丢最旧的。
    public static let limit = 20

    public static func directory(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// 改动之前调用：把磁盘上当前的 `project.json` 存一份。
    /// 内容与最新一份快照相同时不重复存。
    @discardableResult
    public static func snapshotCurrent(in packageURL: URL) throws -> SnapshotEntry? {
        try writeSnapshot(in: packageURL, clearingRedo: true)
    }

    /// 新的改动落盘时清掉 redo 栈；redo 自己回放时要保留。
    @discardableResult
    private static func writeSnapshot(in packageURL: URL, clearingRedo: Bool) throws -> SnapshotEntry? {
        let metadataURL = ProjectPackage.metadataURL(in: packageURL)
        guard let data = try? Data(contentsOf: metadataURL), !data.isEmpty else { return nil }
        let project = try ProjectCoding.decode(data)

        let dir = directory(in: packageURL)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let newest = try list(in: packageURL).first,
           let newestData = try? Data(contentsOf: dir.appendingPathComponent(newest.id + ".json")),
           newestData == data {
            return newest
        }

        let stamp = stampFormatter.string(from: Date())
        let name = "\(stamp)-r\(project.revision)"
        let url = dir.appendingPathComponent(name + ".json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }

        prune(in: packageURL)
        if clearingRedo {
            clearRedo(in: packageURL)
        }
        return SnapshotEntry(
            id: name,
            title: project.title,
            revision: project.revision,
            savedAt: Date(),
            byteCount: data.count
        )
    }

    /// 新的在前。
    public static func list(in packageURL: URL) throws -> [SnapshotEntry] {
        try list(inDirectory: directory(in: packageURL))
    }

    /// redo 栈，新的在前。
    public static func redoList(in packageURL: URL) throws -> [SnapshotEntry] {
        try list(inDirectory: redoDirectory(in: packageURL))
    }

    public static func redoDirectory(in packageURL: URL) -> URL {
        directory(in: packageURL).appendingPathComponent("redo", isDirectory: true)
    }

    public static func clearRedo(in packageURL: URL) {
        try? FileManager.default.removeItem(at: redoDirectory(in: packageURL))
    }

    private static func list(inDirectory dir: URL) throws -> [SnapshotEntry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        let entries: [SnapshotEntry] = names
            .filter { $0.hasSuffix(".json") }
            .compactMap { name in
                let url = dir.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: url),
                      let project = try? ProjectCoding.decode(data) else { return nil }
                return SnapshotEntry(
                    id: String(name.dropLast(5)),
                    title: project.title,
                    revision: project.revision,
                    savedAt: fileDate(url) ?? project.modifiedAt,
                    byteCount: data.count
                )
            }
        return entries.sorted { $0.id > $1.id }
    }

    /// 把某一份快照写回 `project.json`，并删掉它和比它新的快照。
    @discardableResult
    public static func restore(_ id: String, in packageURL: URL) throws -> StoryProject {
        let dir = directory(in: packageURL)
        let url = dir.appendingPathComponent(id + ".json")
        let data = try Data(contentsOf: url)
        let project = try ProjectCoding.decode(data)

        try data.write(to: ProjectPackage.metadataURL(in: packageURL), options: .atomic)

        for entry in try list(in: packageURL) where entry.id >= id {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(entry.id + ".json"))
        }
        return project
    }

    /// 最近一份快照，没有就返回 nil。
    public static func latest(in packageURL: URL) throws -> SnapshotEntry? {
        try list(in: packageURL).first
    }

    /// 撤回最近 `steps` 步，返回每一份被写回的快照。撤回前把当前状态压进 redo 栈。
    @discardableResult
    public static func undo(steps: Int, in packageURL: URL) throws -> [SnapshotEntry] {
        var restored: [SnapshotEntry] = []
        for _ in 0..<max(1, steps) {
            guard let latest = try latest(in: packageURL) else { break }
            _ = recordRedoPoint(in: packageURL)
            _ = try restore(latest.id, in: packageURL)
            restored.append(latest)
        }
        return restored
    }

    /// 撤回前留一份前进状态。连续撤回时内容相同就不重复压栈。
    @discardableResult
    public static func recordRedoPoint(in packageURL: URL) -> SnapshotEntry? {
        let metadataURL = ProjectPackage.metadataURL(in: packageURL)
        guard let data = try? Data(contentsOf: metadataURL), !data.isEmpty,
              let project = try? ProjectCoding.decode(data) else { return nil }
        let dir = redoDirectory(in: packageURL)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let newest = try? list(inDirectory: dir).first,
           let newestData = try? Data(contentsOf: dir.appendingPathComponent(newest.id + ".json")),
           newestData == data {
            return newest
        }
        let name = "\(stampFormatter.string(from: Date()))-r\(project.revision)"
        let url = dir.appendingPathComponent(name + ".json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return SnapshotEntry(
            id: name,
            title: project.title,
            revision: project.revision,
            savedAt: Date(),
            byteCount: data.count
        )
    }

    /// 重做 `steps` 步：把当前状态压回普通历史，再把 redo 栈顶写回。
    @discardableResult
    public static func redo(steps: Int, in packageURL: URL) throws -> [SnapshotEntry] {
        var redone: [SnapshotEntry] = []
        for _ in 0..<max(1, steps) {
            guard let latest = try redoList(in: packageURL).first else { break }
            let url = redoDirectory(in: packageURL).appendingPathComponent(latest.id + ".json")
            guard let data = try? Data(contentsOf: url) else { break }
            _ = try writeSnapshot(in: packageURL, clearingRedo: false)
            try data.write(to: ProjectPackage.metadataURL(in: packageURL), options: .atomic)
            try? FileManager.default.removeItem(at: url)
            redone.append(latest)
        }
        return redone
    }

    public static func prune(in packageURL: URL) {
        let dir = directory(in: packageURL)
        guard let entries = try? list(in: packageURL), entries.count > limit else { return }
        for entry in entries.dropFirst(limit) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(entry.id + ".json"))
        }
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()

    private static func fileDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))
            .flatMap { $0[.creationDate] as? Date }
    }
}
