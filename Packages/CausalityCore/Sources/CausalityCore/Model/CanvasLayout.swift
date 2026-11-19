import Foundation

/// 故事图的自动排布。
///
/// 卡片按阅读顺序排成蛇形：一行从左到右，下一行从右往左接回去。
/// 相邻两张卡最多隔一个格子，连线不会横穿整屏。
public enum CanvasLayout {
    public static let defaultColumns = 3
    public static let cardWidth: Double = 210
    public static let columnGap: Double = 110
    public static let rowHeight: Double = 240
    public static let origin = CanvasPoint(x: 120, y: 120)
    /// 自适应列数的目标：每列大约占 240pt，扣掉左右留白。
    public static let autoColumnPitch: Double = 240
    public static let autoHorizontalPadding: Double = 48

    /// 阅读顺序：按章、按章内顺序表，最后是没挂章的灵感卡。
    public static func readingOrder(of project: StoryProject) -> [NodeID] {
        var ordered: [NodeID] = []
        var seen: Set<NodeID> = []
        for chapter in project.chapters {
            for id in chapter.order where project.node(id) != nil && !seen.contains(id) {
                ordered.append(id)
                seen.insert(id)
            }
        }
        for node in project.nodes where !seen.contains(node.id) {
            ordered.append(node.id)
        }
        return ordered
    }

    /// 按画布宽度算蛇形列数。宽屏多排、窄屏少排；至少一列。
    public static func columns(forWidth width: Double) -> Int {
        let usable = max(0, width - autoHorizontalPadding)
        return max(1, Int((usable + autoColumnPitch / 2) / autoColumnPitch))
    }

    /// 蛇形坐标表。
    public static func serpentine(
        project: StoryProject,
        columns: Int = defaultColumns,
        cardWidth: Double = cardWidth,
        columnGap: Double = columnGap,
        rowHeight: Double = rowHeight,
        origin: CanvasPoint = origin
    ) -> [NodeID: CanvasPoint] {
        let width = max(1, columns)
        var points: [NodeID: CanvasPoint] = [:]
        for (index, id) in readingOrder(of: project).enumerated() {
            let row = index / width
            let slot = index % width
            let column = row % 2 == 0 ? slot : width - 1 - slot
            points[id] = CanvasPoint(
                x: origin.x + Double(column) * (cardWidth + columnGap),
                y: origin.y + Double(row) * rowHeight
            )
        }
        return points
    }

    /// 拖动后的落点：起点 + 位移 / 缩放，左上不越过原点。
    ///
    /// 起点必须是**按下那一刻**的位置。拖动过程中卡片本身已经跟着位移走了，
    /// 再拿位移后的位置当基准，落点会多走一整段位移。
    public static func dragged(
        from start: CanvasPoint,
        dx: Double,
        dy: Double,
        zoom: Double
    ) -> CanvasPoint {
        let scale = zoom <= 0.01 ? 1 : zoom
        return CanvasPoint(
            x: max(0, start.x + dx / scale),
            y: max(0, start.y + dy / scale)
        )
    }

    /// 把蛇形坐标变成一组编辑操作，已经在那儿的卡不动。
    public static func arrange(project: StoryProject, columns: Int = defaultColumns) -> [EditOperation] {
        let target = serpentine(project: project, columns: columns)
        var operations: [EditOperation] = []
        for (id, point) in target.sorted(by: { $0.key.rawValue.uuidString < $1.key.rawValue.uuidString }) {
            guard project.canvas[id] != point else { continue }
            operations += ProjectMutations.setCanvasPoint(point, for: id, in: project)
        }
        return operations
    }
}
