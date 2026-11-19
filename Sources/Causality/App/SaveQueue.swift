import Foundation
import CausalityCore

/// 落盘队列：一次只写一个包，调用方在主线程拍快照后交给它。
///
/// 写盘包括编码、配图落盘、列目录清理与备份轮换，放主线程会让敲字卡顿。
/// 用 actor 天然串行，避免同一个包两个写并发。
actor SaveQueue {
    private var inFlight = false
    /// 故障演练与测试用：写盘前停一下，模拟慢盘。
    private var beforeSave: (@Sendable () async -> Void)?

    func setBeforeSave(_ hook: (@Sendable () async -> Void)?) {
        beforeSave = hook
    }

    func save(
        _ project: StoryProject,
        to url: URL,
        assets: [AssetID: Data],
        expecting: PackageStamp?,
        copyingAssetsFrom source: URL? = nil
    ) async throws -> SaveReport {
        inFlight = true
        defer { inFlight = false }
        await beforeSave?()
        return try ProjectPackage.save(
            project,
            to: url,
            newAssetData: assets,
            expecting: expecting,
            copyingAssetsFrom: source
        )
    }
}
