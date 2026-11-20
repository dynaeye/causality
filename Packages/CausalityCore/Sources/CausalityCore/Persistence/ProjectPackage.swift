import CryptoKit
import Foundation

public enum PackageError: Error, CustomStringConvertible, LocalizedError, Equatable {
    case notAPackage(String)
    case missingMetadata(String)
    case unreadableMetadata(String)
    case unsupportedSchema(found: Int, supported: Int)
    case assetWriteFailed(String)
    case conflict(expected: PackageStamp, current: PackageStamp?)

    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case let .notAPackage(path): CoreText.format("不是可读的项目包：%@", path)
        case let .missingMetadata(path): CoreText.format("缺少 project.json：%@", path)
        case let .unreadableMetadata(reason): CoreText.format("project.json 无法解析：%@", reason)
        case let .unsupportedSchema(found, supported):
            CoreText.format(
                "工程包版本 %lld 比当前 App 支持的 %lld 新，请先更新 App 再打开。",
                found, supported
            )
        case let .assetWriteFailed(reason): CoreText.format("配图写入失败：%@", reason)
        case let .conflict(expected, current):
            CoreText.format(
                "工程包已被其它程序改动（%@）。先重新打开，或另存为。",
                expected.conflictDetail(with: current)
            )
        }
    }
}

/// 工程包在某一刻的版本指纹。保存时可以带上打开时的指纹，磁盘变了就拒绝覆盖。
public struct PackageStamp: Sendable, Equatable {
    public var revision: Int
    public var modifiedAt: Date
    /// project.json 的文件修改时间。CLI / MCP 的改动不一定抬 revision，靠它兜底。
    public var fileModifiedAt: Date?

    public init(revision: Int, modifiedAt: Date, fileModifiedAt: Date? = nil) {
        self.revision = revision
        self.modifiedAt = modifiedAt
        self.fileModifiedAt = fileModifiedAt
    }

    /// 给冲突提示用的一句人话。CLI / MCP 的改动常常不抬 revision，这时说文件被改写。
    public func conflictDetail(with current: PackageStamp?) -> String {
        guard let current else { return CoreText.text("磁盘上的 project.json 不见了") }
        if current.revision != revision {
            return "revision \(revision) → \(current.revision)"
        }
        return CoreText.text("磁盘上的 project.json 已被改写")
    }
}

/// 保存过程中的注入点，用于验收“写到一半退出”。
public struct SaveHooks: Sendable {
    public var beforeMetadataCommit: (@Sendable () throws -> Void)?

    public init(beforeMetadataCommit: (@Sendable () throws -> Void)? = nil) {
        self.beforeMetadataCommit = beforeMetadataCommit
    }
}

/// 一次保存做了什么。验收用例靠它判断“改一句台词时原图零写入”。
public struct SaveReport: Sendable, Equatable {
    public var packageURL: URL
    public var writtenAssetIDs: [AssetID]
    /// 从别的工程包复制过来的图片（另存为时）。
    public var copiedAssetIDs: [AssetID]
    public var reusedAssetIDs: [AssetID]
    public var missingAssetIDs: [AssetID]
    public var prunedAssetFileNames: [String]
    public var metadataByteCount: Int
    public var previousVersionBackedUp: Bool
}

public struct LoadedProject: Sendable {
    public var project: StoryProject
    public var packageURL: URL
    public var warnings: [String]
    public var recoveredFromPreviousVersion: Bool
}

public enum Digest {
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum ProjectCoding {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Formatters.shared.withFraction.string(from: date))
        }
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = Formatters.shared.withFraction.date(from: text) {
                return date
            }
            if let date = Formatters.shared.plain.date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: CoreText.format("无法解析时间：%@", text)
            )
        }
        return decoder
    }

    public static func encode(_ project: StoryProject) throws -> Data {
        try makeEncoder().encode(project)
    }

    public static func decode(_ data: Data) throws -> StoryProject {
        try makeDecoder().decode(StoryProject.self, from: data)
    }

    /// 时间戳格式化器只建一次。每个日期现建一个 ISO8601DateFormatter 会让打开工程慢两个数量级
    /// （500 张卡大约两千五百个日期）。ISO8601DateFormatter 可以并发读字符串。
    private final class Formatters: @unchecked Sendable {
        static let shared = Formatters()

        let withFraction: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        let plain: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()
    }
}

/// .causal 工程包：一个目录，含一份元数据快照与按需增量写入的图片。
public enum ProjectPackage {
    public static let fileExtension = "causal"

    public static func isProjectPackage(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == fileExtension
    }
    public static let metadataFileName = "project.json"
    public static let previousMetadataFileName = "project.previous.json"
    public static let assetsDirectoryName = "assets"
    /// 不再被引用的配图先搬到这里，保留几天再删。图片是用户的原始素材，删掉就没法恢复。
    public static let trashDirectoryName = ".trash"
    public static let trashRetentionDays = 7

    public static func metadataURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(metadataFileName, isDirectory: false)
    }

    public static func previousMetadataURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(previousMetadataFileName, isDirectory: false)
    }

    public static func assetsDirectory(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(assetsDirectoryName, isDirectory: true)
    }

    public static func assetURL(for asset: Asset, in packageURL: URL) -> URL {
        assetsDirectory(in: packageURL).appendingPathComponent(asset.fileName, isDirectory: false)
    }

    // MARK: 保存

    @discardableResult
    public static func save(
        _ project: StoryProject,
        to packageURL: URL,
        newAssetData: [AssetID: Data] = [:],
        expecting: PackageStamp? = nil,
        copyingAssetsFrom sourcePackageURL: URL? = nil,
        hooks: SaveHooks = SaveHooks()
    ) throws -> SaveReport {
        try PackageLock.withExclusiveLock(at: packageURL) {
            if let expecting {
                let current = stamp(in: packageURL)
                guard current == expecting else {
                    throw PackageError.conflict(expected: expecting, current: current)
                }
            }
            return try saveUnlocked(
                project,
                to: packageURL,
                newAssetData: newAssetData,
                copyingAssetsFrom: sourcePackageURL,
                hooks: hooks
            )
        }
    }

    /// 用一份已经写完整的包替换 `destination`。
    ///
    /// 旧包先挪到同目录的隐藏临时名，替换成功再进废纸篓；替换失败就放回原处。
    /// 草稿转正、另存为和复制工程都走这里，中途失败不会把旧包先删掉。
    public static func replacePackage(at destination: URL, with completePackage: URL) throws {
        let fileManager = FileManager.default
        if destination.standardizedFileURL == completePackage.standardizedFileURL { return }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard fileManager.fileExists(atPath: destination.path) else {
            try fileManager.moveItem(at: completePackage, to: destination)
            return
        }

        let backup = destination.deletingLastPathComponent()
            .appendingPathComponent(
                "\(destination.lastPathComponent).\(UUID().uuidString.prefix(8)).old",
                isDirectory: true
            )
        try fileManager.moveItem(at: destination, to: backup)
        do {
            try fileManager.moveItem(at: completePackage, to: destination)
        } catch {
            // 换失败：旧包放回原处，草稿和工程都不能凭空消失。
            try? fileManager.removeItem(at: destination)
            try? fileManager.moveItem(at: backup, to: destination)
            throw error
        }
        try? fileManager.trashItem(at: backup, resultingItemURL: nil)
    }

    /// 磁盘上当前版本的指纹。优先读 project.json；读不到返回 nil。
    public static func stamp(in packageURL: URL) -> PackageStamp? {
        let url = metadataURL(in: packageURL)
        guard let data = try? Data(contentsOf: url),
              let project = try? ProjectCoding.decode(data) else { return nil }
        let fileModifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        return PackageStamp(
            revision: project.revision,
            modifiedAt: project.modifiedAt,
            fileModifiedAt: fileModifiedAt
        )
    }

    /// 真正落盘。调用方要先拿到 `PackageLock`。
    private static func saveUnlocked(
        _ project: StoryProject,
        to packageURL: URL,
        newAssetData: [AssetID: Data],
        copyingAssetsFrom sourcePackageURL: URL?,
        hooks: SaveHooks
    ) throws -> SaveReport {
        let fileManager = FileManager.default
        let assetsURL = assetsDirectory(in: packageURL)
        try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)

        var written: [AssetID] = []
        var copied: [AssetID] = []
        var reused: [AssetID] = []
        var missing: [AssetID] = []
        let copySource = sourcePackageURL.flatMap { source in
            source.standardizedFileURL == packageURL.standardizedFileURL ? nil : source
        }

        for asset in project.assets.sorted(by: { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }) {
            let destination = assetURL(for: asset, in: packageURL)
            if fileManager.fileExists(atPath: destination.path), sizeMatches(asset, at: destination) {
                reused.append(asset.id)
                continue
            }
            if let data = newAssetData[asset.id] {
                do {
                    try data.write(to: destination, options: .atomic)
                } catch {
                    throw PackageError.assetWriteFailed("\(asset.fileName)：\(error.localizedDescription)")
                }
                written.append(asset.id)
                continue
            }
            // 另存为：包里已有的图片从原包复制过来，别只留下一条断掉的引用。
            if let copySource, copyAsset(asset, from: copySource, to: destination) {
                copied.append(asset.id)
                continue
            }
            missing.append(asset.id)
        }

        // 图片先落盘，元数据最后提交：提交前退出，磁盘上仍是上一版完整工程。
        try hooks.beforeMetadataCommit?()

        var stored = project
        ProjectMigration.upgrade(&stored)
        let metadataData = try ProjectCoding.encode(stored)
        let metadataURL = metadataURL(in: packageURL)
        let previousURL = previousMetadataURL(in: packageURL)

        // 只有真的读到当前的元数据才覆盖上一版备份。
        // 直接 copyItem 在 project.json 不可读时会把目录或损坏文件搬过去，反而毁掉回退点。
        var backedUp = false
        if let current = try? Data(contentsOf: metadataURL), !current.isEmpty {
            if (try? current.write(to: previousURL, options: .atomic)) != nil {
                backedUp = true
            }
        }

        do {
            try metadataData.write(to: metadataURL, options: .atomic)
        } catch {
            throw PackageError.unreadableMetadata(error.localizedDescription)
        }

        let pruned = pruneOrphanAssets(in: packageURL, keeping: Set(project.assets.map(\.fileName)))

        return SaveReport(
            packageURL: packageURL,
            writtenAssetIDs: written,
            copiedAssetIDs: copied,
            reusedAssetIDs: reused,
            missingAssetIDs: missing,
            prunedAssetFileNames: pruned,
            metadataByteCount: metadataData.count,
            previousVersionBackedUp: backedUp
        )
    }

    // MARK: 读取

    public static func load(from packageURL: URL) throws -> LoadedProject {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: packageURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PackageError.notAPackage(packageURL.path)
        }

        let metadataURL = metadataURL(in: packageURL)
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            throw PackageError.missingMetadata(packageURL.path)
        }

        var warnings: [String] = []
        var recovered = false

        var project: StoryProject
        do {
            project = try ProjectCoding.decode(Data(contentsOf: metadataURL))
        } catch {
            let previousURL = previousMetadataURL(in: packageURL)
            guard fileManager.fileExists(atPath: previousURL.path),
                  let recoveredProject = try? ProjectCoding.decode(Data(contentsOf: previousURL)) else {
                throw PackageError.unreadableMetadata(error.localizedDescription)
            }
            warnings.append(CoreText.text("project.json 损坏，已回退到上一版本。"))
            recovered = true
            project = recoveredProject
        }

        guard project.schemaVersion <= StoryProject.currentSchemaVersion else {
            throw PackageError.unsupportedSchema(
                found: project.schemaVersion,
                supported: StoryProject.currentSchemaVersion
            )
        }

        if let note = ProjectMigration.warning(
            found: project.schemaVersion,
            current: StoryProject.currentSchemaVersion
        ) {
            warnings.append(note)
            ProjectMigration.upgrade(&project)
        }

        warnings.append(contentsOf: ProjectValidator.issues(in: project))

        for asset in project.assets where !fileManager.fileExists(atPath: assetURL(for: asset, in: packageURL).path) {
            warnings.append(CoreText.format("配图文件缺失：%@", asset.fileName))
        }

        return LoadedProject(
            project: project,
            packageURL: packageURL,
            warnings: warnings,
            recoveredFromPreviousVersion: recovered
        )
    }

    // MARK: 内部

    /// 把原包里的一张图复制进新包。源文件缺失或大小对不上就不复制，留给报告说。
    private static func copyAsset(_ asset: Asset, from sourcePackageURL: URL, to destination: URL) -> Bool {
        let fileManager = FileManager.default
        let source = assetURL(for: asset, in: sourcePackageURL)
        guard fileManager.fileExists(atPath: source.path), sizeMatches(asset, at: source) else { return false }
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: destination)
            return true
        } catch {
            return false
        }
    }

    private static func sizeMatches(_ asset: Asset, at url: URL) -> Bool {
        guard let expected = asset.byteCount else { return true }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int else {
            return false
        }
        return size == expected
    }

    /// 把不再引用的配图搬进 `assets/.trash/<时间戳>/`，而不是直接删除。
    private static func pruneOrphanAssets(in packageURL: URL, keeping fileNames: Set<String>) -> [String] {
        let fileManager = FileManager.default
        let assetsURL = assetsDirectory(in: packageURL)
        guard let contents = try? fileManager.contentsOfDirectory(atPath: assetsURL.path) else { return [] }
        let orphans = contents.filter { !fileNames.contains($0) && !$0.hasPrefix(".") }
        guard !orphans.isEmpty else { return [] }

        let stamp = trashStampFormatter.string(from: Date())
        let trashURL = assetsURL
            .appendingPathComponent(trashDirectoryName, isDirectory: true)
            .appendingPathComponent(stamp, isDirectory: true)
        try? fileManager.createDirectory(at: trashURL, withIntermediateDirectories: true)

        var removed: [String] = []
        for name in orphans {
            let source = assetsURL.appendingPathComponent(name)
            let destination = trashURL.appendingPathComponent(name)
            if (try? fileManager.moveItem(at: source, to: destination)) != nil {
                removed.append(name)
            }
        }
        return removed.sorted()
    }

    /// 清掉回收站里超过保留期的目录。启动或保存时顺手跑一次。
    @discardableResult
    public static func purgeAssetTrash(in packageURL: URL, olderThan days: Int = trashRetentionDays) -> Int {
        let fileManager = FileManager.default
        let trashURL = assetsDirectory(in: packageURL).appendingPathComponent(trashDirectoryName, isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return 0 }

        let deadline = Date().addingTimeInterval(-Double(days) * 86_400)
        var purged = 0
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified < deadline, (try? fileManager.removeItem(at: entry)) != nil {
                purged += 1
            }
        }
        return purged
    }

    private static let trashStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
