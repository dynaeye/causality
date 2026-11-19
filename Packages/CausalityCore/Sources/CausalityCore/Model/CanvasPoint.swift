import Foundation

/// 画布坐标。与故事模型分开保存，避免布局改动污染叙述数据。
public struct CanvasPoint: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = CanvasPoint(x: 0, y: 0)

    public func offsetBy(dx: Double, dy: Double) -> CanvasPoint {
        CanvasPoint(x: x + dx, y: y + dy)
    }
}
