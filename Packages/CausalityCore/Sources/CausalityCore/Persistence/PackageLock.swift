import Darwin
import Foundation

/// 同一工程包的跨进程写锁。
///
/// App、`causal` 与 MCP 都可能同时写同一个包；落盘本身是原子的，但
/// 「备份上一版 → 写新一版」这一串需要串起来，否则两个进程会互相覆盖备份。
/// 锁只覆盖一次保存，不阻止「打开后各自改」的丢更新；那种情况要靠会话级互斥。
enum PackageLock {
    static func withExclusiveLock<T>(at packageURL: URL, _ body: () throws -> T) rethrows -> T {
        try? FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let lockURL = packageURL.appendingPathComponent(".write.lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return try body() }
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        flock(fd, LOCK_EX)
        return try body()
    }
}
