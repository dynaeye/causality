import Foundation

/// 工程包版本迁移。
///
/// `StoryProject` 的解码本身是宽松的：新字段缺失按默认值补，旧包能直接打开。
/// 这里管的是另一件事——**版本号**：保存时统一写成当前版本，读到时把更老的版本
/// 抬到当前版本并在 warnings 里说明，让作者知道内容被升级过。
public enum ProjectMigration {
    /// 把工程抬到当前 schema 版本，返回是否动过。
    @discardableResult
    public static func upgrade(_ project: inout StoryProject) -> Bool {
        guard project.schemaVersion < StoryProject.currentSchemaVersion else { return false }
        project.schemaVersion = StoryProject.currentSchemaVersion
        return true
    }

    /// 读到更老的工程包时，给一条可读提示。
    public static func warning(found: Int, current: Int) -> String? {
        guard found < current else { return nil }
        return CoreText.format("工程包是 v%lld 版本，已按 v%lld 读取并升级。", found, current)
    }
}
