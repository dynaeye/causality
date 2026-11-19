import AppKit
import CausalityCore
import SwiftUI

/// 把故事图导出成 PNG。
///
/// 用固定的浅色版式（白底、深字、灰线、主线用强调色），方便贴进策划笔记与打印；
/// 与界面主题无关，换主题不影响导出结果。
enum CanvasImageExport {
    /// 导出最长边上限（像素）。超过就降采样，避免 500 节点出图把内存打满。
    static let maxPixel: CGFloat = 8000
    private static let cardWidth: CGFloat = 210
    private static let cardHeight: CGFloat = 150
    private static let padding: CGFloat = 56

    /// 按内容尺寸算出实际缩放：默认 2 倍，长边超过 `maxPixel` 就降，最低 0.5。
    static func scale(for bounds: CGSize, preferred: CGFloat = 2) -> CGFloat {
        let longest = max(bounds.width, bounds.height)
        guard longest > 0 else { return preferred }
        return max(0.5, min(preferred, maxPixel / longest))
    }

    @MainActor
    static func makePNG(
        project: StoryProject,
        preferredScale: CGFloat = 2,
        language: InterfaceLanguage = .current
    ) -> Data? {
        let rects = layout(project)
        guard !rects.isEmpty else { return nil }
        let bounds = rects.values.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -padding, dy: -padding)
        let scale = scale(for: bounds.size, preferred: preferredScale)

        let renderer = ImageRenderer(
            content: ExportCanvas(project: project, rects: normalized(rects), size: bounds.size)
                .frame(width: bounds.width, height: bounds.height)
                // 导出图里的卡片标签跟作品语言。
                .environment(\.locale, language.locale)
        )
        renderer.scale = scale
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func normalized(_ rects: [NodeID: CGRect]) -> [NodeID: CGRect] {
        let bounds = rects.values.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -padding, dy: -padding)
        return rects.mapValues { rect in
            CGRect(
                x: rect.minX - bounds.minX,
                y: rect.minY - bounds.minY,
                width: rect.width,
                height: rect.height
            )
        }
    }

    /// 有手动坐标就用，没摆过的卡按蛇形补齐。
    static func layout(_ project: StoryProject) -> [NodeID: CGRect] {
        let fallback = CanvasLayout.serpentine(project: project)
        var rects: [NodeID: CGRect] = [:]
        for node in project.nodes {
            // 灵感卡只有真在画布上摆过才画进来，免得把参考材料混进故事图。
            let point: CanvasPoint
            if let stored = project.canvas[node.id] {
                point = stored
            } else if node.status == .draft, let auto = fallback[node.id] {
                point = auto
            } else {
                continue
            }
            rects[node.id] = CGRect(
                x: CGFloat(point.x),
                y: CGFloat(point.y),
                width: cardWidth,
                height: cardHeight
            )
        }
        return rects
    }
}

private struct ExportCanvas: View {
    let project: StoryProject
    let rects: [NodeID: CGRect]
    let size: CGSize

    private let ink = Color(red: 0.11, green: 0.11, blue: 0.12)
    private let sub = Color(red: 0.38, green: 0.38, blue: 0.40)
    private let paper = Color.white
    private let card = Color(red: 0.98, green: 0.97, blue: 0.96)
    private let edge = Color(red: 0.72, green: 0.69, blue: 0.66)
    private let accent = Color(red: 0.70, green: 0.42, blue: 0.16)

    var body: some View {
        ZStack(alignment: .topLeading) {
            paper
            Canvas { context, _ in
                for link in links {
                    draw(link, in: &context)
                }
            }
            ForEach(project.nodes) { node in
                if let rect = rects[node.id] {
                    cardView(node)
                        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private struct Link {
        var from: CGRect
        var to: CGRect
        var color: Color
        var width: CGFloat
    }

    private var links: [Link] {
        let mainline = Mainline.derive(in: project)
        return project.edges.compactMap { edge in
            guard let from = rects[edge.from], let to = rects[edge.to] else { return nil }
            let isMain = mainline.contains(edge: edge.id)
            let color: Color = isMain ? accent : edgeColor(edge.kind)
            return Link(from: from, to: to, color: color, width: isMain ? 2.2 : 1.2)
        }
    }

    private func edgeColor(_ kind: EdgeKind) -> Color {
        switch kind {
        case .cause: Color(red: 0.55, green: 0.45, blue: 0.36)
        case .choice: Color(red: 0.42, green: 0.48, blue: 0.62)
        case .condition: Color(red: 0.45, green: 0.55, blue: 0.45)
        case .plain: edge
        }
    }

    private func draw(_ link: Link, in context: inout GraphicsContext) {
        let start = anchor(of: link.from, towards: link.to)
        let end = anchor(of: link.to, towards: link.from)
        var path = Path()
        path.move(to: start)
        let dx = (end.x - start.x) / 2
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x + dx, y: start.y),
            control2: CGPoint(x: end.x - dx, y: end.y)
        )
        context.stroke(path, with: .color(link.color), lineWidth: link.width)

        // 箭头
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head: CGFloat = 6
        var arrow = Path()
        arrow.move(to: end)
        arrow.addLine(to: CGPoint(x: end.x - head * cos(angle - 0.45), y: end.y - head * sin(angle - 0.45)))
        arrow.addLine(to: CGPoint(x: end.x - head * cos(angle + 0.45), y: end.y - head * sin(angle + 0.45)))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(link.color))
    }

    /// 从卡片边框上找一个出线点：横向为主时走左右边，纵向为主时走上下边。
    private func anchor(of rect: CGRect, towards other: CGRect) -> CGPoint {
        let dx = other.midX - rect.midX
        let dy = other.midY - rect.midY
        if abs(dx) >= abs(dy) {
            return CGPoint(x: dx >= 0 ? rect.maxX : rect.minX, y: rect.midY)
        }
        return CGPoint(x: rect.midX, y: dy >= 0 ? rect.maxY : rect.minY)
    }

    private func cardView(_ node: StoryNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(LocalizedStringKey(node.kind.displayName))
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(sub)
                if node.isEntry {
                    Text("入口")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(accent)
                }
                Spacer(minLength: 0)
            }
            Text(node.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink)
                .lineLimit(2)
            Text(node.summary.isEmpty ? node.body : node.summary)
                .font(.system(size: 10.5))
                .foregroundStyle(sub)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }
}
