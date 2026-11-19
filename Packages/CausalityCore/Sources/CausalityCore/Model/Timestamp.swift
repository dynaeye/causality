import Foundation

/// 时间戳统一截到毫秒，保证 JSON 往返后逐字段相等。
public enum Timestamp {
    public static func now() -> Date {
        let milliseconds = (Date().timeIntervalSince1970 * 1000).rounded(.down)
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    public static func quantized(_ date: Date) -> Date {
        let milliseconds = (date.timeIntervalSince1970 * 1000).rounded(.down)
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
