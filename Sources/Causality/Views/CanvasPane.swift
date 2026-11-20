import CausalityCore
import SwiftUI

struct CanvasPane: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession
    /// 右栏浮层的宽度：滚轮落在它下面时交回面板，别当成画布平移。
    var inspectorWidth: CGFloat = 0

    private let cardSize = CGSize(width: 204, height: 204)

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize = .zero
    @State private var zoomStart: CGFloat = 1
    @State private var lastSize: CGSize = .zero
    @State private var userAdjusted = false
    @State private var hoveredEdge: EdgeID?
    @State private var draggingNode: NodeID?
    @State private var dragOffset: CGSize = .zero
    @State private var dragBase: CanvasPoint?
    @State private var threadFilter: ThreadID?
    @State private var edgeCache = EdgeGeometryCache()
    @State private var layoutCache = CanvasPointCache()

    var body: some View {
        GeometryReader { proxy in
            let project = session.project
            let allNodes = project?.nodes ?? []
            // 正式场景都画；念头只要接过线也画，否则它身上的连线会凭空消失。
            let connected = Set((project?.edges ?? []).flatMap { [$0.from, $0.to] })
            let nodes = allNodes.filter { $0.status == .draft || connected.contains($0.id) }
            let points = displayPoints(nodes: nodes, project: project, width: proxy.size.width)
            let threadNodes: Set<NodeID>? = threadFilter.flatMap { id in
                session.project?.threads.first { $0.id == id }
            }.map { thread in
                Set(thread.entries.map(\.nodeID))
            }
            let contentRect = boundingRect(points: points, in: proxy.size)
            let visibleRect = visibleModelRect(in: proxy.size)

            ZStack(alignment: .topLeading) {
                theme.background

                Canvas { context, _ in
                    drawEdges(context: context, points: points, visible: visibleRect, width: proxy.size.width)
                }
                .frame(width: contentRect.width, height: contentRect.height)
                .allowsHitTesting(false)


                // SwiftUI 只创建视口内的卡；500 节点时不要把 500 个条件视图都交给 diff。
                ForEach(visibleNodes(nodes: nodes, points: points, visible: visibleRect)) { node in
                    if let point = points[node.id] {
                        card(node: node, point: point)
                            .opacity(threadNodes == nil || threadNodes?.contains(node.id) == true ? 1 : 0.15)
                            .position(
                                x: point.x + cardSize.width / 2 + (draggingNode == node.id ? dragOffset.width : 0),
                                y: point.y + cardSize.height / 2 + (draggingNode == node.id ? dragOffset.height : 0)
                            )
                    }
                }
            }
            .frame(width: contentRect.width, height: contentRect.height, alignment: .topLeading)
            .coordinateSpace(name: "storyCanvas")
            .scaleEffect(zoom, anchor: .topLeading)
            .offset(pan)
            // 画布内容再大也只占它自己的格，不参与外层布局，右侧详情不会跟着漂。
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(magnifyGesture)
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 8) {
                    CanvasScrollHint()
                    canvasControls
                }
            }
            .overlay(alignment: .bottomLeading) {
                threadFilterMenu
                    .padding(14)
            }
            .onContinuousHover { phase in
                switch phase {
                case let .active(point):
                    hoveredEdge = nearestEdge(to: point, points: points, rects: points, width: proxy.size.width)
                case .ended:
                    hoveredEdge = nil
                }
            }
            .onAppear {
                fitContent(in: proxy.size, points: points)
            }
            .onChange(of: proxy.size) { _, newSize in
                guard !userAdjusted else { return }
                fitContent(in: newSize, points: points)
            }
            .background(
                ScrollWheelReader(onScroll: { input in
                    handleScroll(input)
                }, trailingCover: inspectorWidth)
            )
        }
        .clipped()
    }

    /// 故事图的线索着色：选中一条线索，只有它上面的卡亮着。
    private var threadFilterMenu: some View {
        Menu {
            Button("全部卡片") { threadFilter = nil }
            if !session.threads.isEmpty {
                Divider()
                ForEach(session.threads) { thread in
                    Button(thread.name) { threadFilter = thread.id }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "paintpalette")
                Text(threadFilter.flatMap { id in session.threads.first { $0.id == id }?.name } ?? InterfaceLanguage.label("按线索着色"))
            }
            .font(.system(size: 11))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(theme.surface.opacity(0.92), in: Capsule())
            .overlay { Capsule().strokeBorder(theme.border, lineWidth: 1) }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(session.threads.isEmpty)
        .help(LocalizedStringKey(session.threads.isEmpty ? "还没有线索" : "只亮这条线索上的卡"))
    }

    // MARK: 手势

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                userAdjusted = true
                pan = CGSize(
                    width: panStart.width + value.translation.width,
                    height: panStart.height + value.translation.height
                )
            }
            .onEnded { _ in panStart = pan }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                userAdjusted = true
                zoom = min(2.5, max(0.3, zoomStart * value.magnification))
            }
            .onEnded { _ in zoomStart = zoom }
    }

    private func cardGesture(for node: StoryNode, origin: CanvasPoint) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("storyCanvas"))
            .onChanged { value in
                if draggingNode != node.id {
                    draggingNode = node.id
                    dragBase = origin
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                defer {
                    draggingNode = nil
                    dragOffset = .zero
                    dragBase = nil
                }
                // 起点取按下那一刻的位置；卡片在拖动中已经偏过位移，不能拿偏过的当基准。
                guard let start = dragBase else { return }
                let newPoint = CanvasLayout.dragged(
                    from: start,
                    dx: value.translation.width,
                    dy: value.translation.height,
                    zoom: zoom
                )
                session.moveCanvasNode(node.id, to: newPoint)
            }
    }

    // MARK: 卡片

    private func card(node: StoryNode, point: CanvasPoint) -> some View {
        let isSelected = session.selectedNodeID == node.id
        // 缩到很小时摘要本来也看不清；只排标题和类型，缩放/平移会轻很多。
        let compact = zoom < 0.7
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                KindBadge(kind: node.kind)
                if node.isEntry {
                    Text("入口")
                        .font(theme.fontMin)
                        .padding(.horizontal, 4)
                        .background(.quaternary, in: Capsule())
                }
                Spacer(minLength: 0)
                if !compact,
                   let assetID = node.coverAssetID,
                   let asset = session.project?.asset(assetID) {
                    CoverThumbnail(asset: asset, packageURL: session.packageURL, maxPixel: 200, cornerRadius: 4)
                        .frame(width: 34, height: 22)
                }
            }
            Text(verbatim: node.title.isEmpty ? InterfaceLanguage.label("未命名场景") : node.title)
                .font(theme.fontCardTitle)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            if !compact {
                Text(verbatim: node.summary.isEmpty ? InterfaceLanguage.label("（还没有摘要）") : node.summary)
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(width: cardSize.width, height: cardSize.height, alignment: .topLeading)
        .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    isSelected ? theme.accent : theme.border,
                    style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: node.status == .idea ? [4, 3] : [])
                )
        }
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture { selectNode(node.id) }
        .contextMenu {
            Button("打开详情") { selectNode(node.id) }
            ReachableEndingsMenu(session: session, nodeID: node.id)
            Divider()
            Button("删除场景", role: .destructive) {
                guard let project = session.project else { return }
                session.apply(ProjectMutations.deleteNode(node.id, in: project), name: InterfaceLanguage.label("删除场景"))
                if session.selectedNodeID == node.id {
                    session.selectedNodeID = nil
                }
            }
        }
        .highPriorityGesture(cardGesture(for: node, origin: point))
    }

    // MARK: 连线

    /// 自适应坐标只跟项目 revision 和画布宽度有关；平移/缩放时直接复用。
    private final class CanvasPointCache {
        private var projectID: UUID?
        private var revision = -1
        private var width: CGFloat = -1
        private var points: [NodeID: CanvasPoint] = [:]

        func points(project: StoryProject, width: CGFloat) -> [NodeID: CanvasPoint] {
            if projectID == project.id, revision == project.revision, self.width == width {
                return points
            }
            projectID = project.id
            revision = project.revision
            self.width = width
            let canonical = CanvasLayout.serpentine(project: project, columns: CanvasLayout.defaultColumns)
            let responsive = CanvasLayout.serpentine(
                project: project,
                columns: CanvasLayout.columns(forWidth: Double(width))
            )
            var next: [NodeID: CanvasPoint] = [:]
            next.reserveCapacity(project.nodes.count)
            for node in project.nodes {
                if let stored = project.canvas[node.id], stored != canonical[node.id] {
                    next[node.id] = stored
                } else if let auto = responsive[node.id] {
                    next[node.id] = auto
                } else {
                    next[node.id] = project.canvas[node.id] ?? CanvasLayout.origin
                }
            }
            points = next
            return points
        }
    }

    /// 连线几何只跟卡片坐标和画布宽度有关；平移/缩放时直接复用。
    private final class EdgeGeometryCache {
        private var projectID: UUID?
        private var revision = -1
        private var width: CGFloat = -1
        private var geometries: [EdgeID: EdgeGeometry] = [:]

        func geometries(
            project: StoryProject,
            width: CGFloat,
            points: [NodeID: CanvasPoint],
            builder: (StoryEdge, [NodeID: CanvasPoint]) -> EdgeGeometry?
        ) -> [EdgeID: EdgeGeometry] {
            if projectID == project.id, revision == project.revision, self.width == width {
                return geometries
            }
            projectID = project.id
            revision = project.revision
            self.width = width
            geometries.removeAll(keepingCapacity: true)
            for edge in project.edges {
                if let geometry = builder(edge, points) {
                    geometries[edge.id] = geometry
                }
            }
            return geometries
        }
    }

    private struct EdgeGeometry {
        var path: Path
        var labelPoint: CGPoint
        var tip: CGPoint
        var direction: CGPoint
        var bounds: CGRect
        /// 采样点，用来判断光标离哪条线最近。
        var samples: [CGPoint]
    }

    private func drawEdges(
        context: GraphicsContext,
        points: [NodeID: CanvasPoint],
        visible: CGRect,
        width: CGFloat
    ) {
        guard let project = session.project else { return }
        // 支线先画、主线后画，交叉时主线压在上面。
        let ordered = project.edges.sorted { lhs, rhs in
            let left = session.mainline.contains(edge: lhs.id)
            let right = session.mainline.contains(edge: rhs.id)
            return right && !left
        }
        let geometries = edgeCache.geometries(project: project, width: width, points: points) { edge, points in
            edgeGeometry(edge, points: points)
        }
        for edge in ordered {
            // 先用两端卡片的外接矩形粗筛，避免给屏幕外的 500 条线建路径和采样点。
            guard let rough = edgeRoughBounds(edge, points: points),
                  visible.intersects(rough) else { continue }
            guard let geometry = geometries[edge.id] else { continue }
            guard visible.intersects(geometry.bounds) else { continue }

            let isMain = session.mainline.contains(edge: edge.id)
            let color = isMain ? theme.accent : theme.lineColor(for: edge.kind)
            let isHovered = hoveredEdge == edge.id
            // 主线：粗一号、实色；支线：细一号、淡下去。
            let baseWidth: CGFloat = isMain ? 3 : 1.3
            let baseOpacity: Double = isMain ? 0.95 : (edge.kind == .plain ? 0.5 : 0.75)
            context.stroke(
                geometry.path,
                with: .color(color.opacity(isHovered ? 1 : baseOpacity)),
                lineWidth: isHovered ? baseWidth + 0.8 : baseWidth
            )

            var arrow = Path()
            let head = isMain ? 9.0 : 6.0
            let half = isMain ? 5.0 : 3.2
            let back = CGPoint(
                x: geometry.tip.x - geometry.direction.x * head,
                y: geometry.tip.y - geometry.direction.y * head
            )
            arrow.move(to: CGPoint(
                x: back.x - geometry.direction.y * half,
                y: back.y + geometry.direction.x * half
            ))
            arrow.addLine(to: geometry.tip)
            arrow.addLine(to: CGPoint(
                x: back.x + geometry.direction.y * half,
                y: back.y - geometry.direction.x * half
            ))
            context.stroke(
                arrow,
                with: .color(color.opacity(isHovered ? 1 : baseOpacity)),
                lineWidth: isMain ? 2 : 1.2
            )

            // 文字只在鼠标移到线上时显示，平时留白。
            if isHovered, !edge.label.isEmpty {
                context.draw(
                    Text(verbatim: (isMain ? InterfaceLanguage.label("主线") + " · " : "") + edge.label)
                        .font(theme.fontMin)
                        .foregroundStyle(color),
                    at: geometry.labelPoint,
                    anchor: .center
                )
            }
        }
    }

    /// 两端卡片的外接矩形，给绘制与悬停做粗筛。
    private func edgeRoughBounds(_ edge: StoryEdge, points: [NodeID: CanvasPoint]) -> CGRect? {
        guard let from = points[edge.from], let to = points[edge.to] else { return nil }
        let fromRect = CGRect(origin: CGPoint(x: from.x, y: from.y), size: cardSize)
        let toRect = CGRect(origin: CGPoint(x: to.x, y: to.y), size: cardSize)
        return fromRect.union(toRect).insetBy(dx: -160, dy: -120)
    }

    private func edgeGeometry(
        _ edge: StoryEdge,
        points: [NodeID: CanvasPoint],
        includeSamples: Bool = true
    ) -> EdgeGeometry? {
        guard let from = points[edge.from], let to = points[edge.to] else { return nil }
        let fromRect = CGRect(origin: CGPoint(x: from.x, y: from.y), size: cardSize)
        let toRect = CGRect(origin: CGPoint(x: to.x, y: to.y), size: cardSize)
        let bounds = fromRect.union(toRect).insetBy(dx: -120, dy: -90)

        if edge.from == edge.to {
            let startPoint = CGPoint(x: fromRect.maxX - 6, y: fromRect.midY - 18)
            let endPoint = CGPoint(x: fromRect.maxX - 6, y: fromRect.midY + 18)
            let bulge = CGPoint(x: fromRect.maxX + 46, y: fromRect.midY)
            var loop = Path()
            loop.move(to: startPoint)
            loop.addCurve(
                to: endPoint,
                control1: CGPoint(x: bulge.x, y: startPoint.y - 22),
                control2: CGPoint(x: bulge.x, y: endPoint.y + 22)
            )
            var samples: [CGPoint] = []
            if includeSamples {
                for step in 0 ... 16 {
                    let t = CGFloat(step) / 16
                    samples.append(
                        cubicPoint(
                            t,
                            startPoint,
                            CGPoint(x: bulge.x, y: startPoint.y - 22),
                            CGPoint(x: bulge.x, y: endPoint.y + 22),
                            endPoint
                        )
                    )
                }
            }
            return EdgeGeometry(
                path: loop,
                labelPoint: CGPoint(x: fromRect.maxX + 30, y: fromRect.midY),
                tip: endPoint,
                direction: CGPoint(x: 0, y: -1),
                bounds: bounds.union(CGRect(x: bulge.x - 20, y: fromRect.midY - 50, width: 80, height: 100)),
                samples: samples
            )
        }

        let startPoint = borderPoint(in: fromRect, toward: CGPoint(x: toRect.midX, y: toRect.midY))
        let endPoint = borderPoint(in: toRect, toward: CGPoint(x: fromRect.midX, y: fromRect.midY))
        let midX = (startPoint.x + endPoint.x) / 2
        let midY = (startPoint.y + endPoint.y) / 2
        let sway = CGFloat(abs(edge.from.rawValue.hashValue) % 2 == 0 ? 18 : -18)
        let control = CGPoint(x: midX, y: midY + sway)
        var path = Path()
        path.move(to: startPoint)
        path.addQuadCurve(to: endPoint, control: control)
        let dx = endPoint.x - control.x
        let dy = endPoint.y - control.y
        let length = max(sqrt(dx * dx + dy * dy), 0.01)
        var samples: [CGPoint] = []
        if includeSamples {
            for step in 0 ... 16 {
                let t = CGFloat(step) / 16
                let inverse = 1 - t
                samples.append(
                    CGPoint(
                        x: inverse * inverse * startPoint.x + 2 * inverse * t * control.x + t * t * endPoint.x,
                        y: inverse * inverse * startPoint.y + 2 * inverse * t * control.y + t * t * endPoint.y
                    )
                )
            }
        }
        return EdgeGeometry(
            path: path,
            labelPoint: CGPoint(
                x: 0.25 * startPoint.x + 0.5 * control.x + 0.25 * endPoint.x,
                y: 0.25 * startPoint.y + 0.5 * control.y + 0.25 * endPoint.y - 10
            ),
            tip: endPoint,
            direction: CGPoint(x: dx / length, y: dy / length),
            bounds: bounds,
            samples: samples
        )
    }

    private func cubicPoint(
        _ t: CGFloat,
        _ p0: CGPoint,
        _ p1: CGPoint,
        _ p2: CGPoint,
        _ p3: CGPoint
    ) -> CGPoint {
        let u = 1 - t
        let a = u * u * u
        let b = 3 * u * u * t
        let c = 3 * u * t * t
        let d = t * t * t
        return CGPoint(
            x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
            y: a * p0.y + b * p1.y + c * p2.y + d * p3.y
        )
    }

    /// 从卡片边框出线，线条不会钻进卡面里。
    private func borderPoint(in rect: CGRect, toward target: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = target.x - center.x
        let dy = target.y - center.y
        guard dx != 0 || dy != 0 else { return center }
        let scaleX = dx == 0 ? CGFloat.infinity : (rect.width / 2) / abs(dx)
        let scaleY = dy == 0 ? CGFloat.infinity : (rect.height / 2) / abs(dy)
        let scale = min(scaleX, scaleY)
        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }

    /// 滚轮平移，⌘ / ⌥ + 滚轮缩放；触控板两指同样是平移，捏合缩放走 magnify 手势。
    private func handleScroll(_ input: ScrollWheelInput) {
        if input.isZoom {
            zoomByScroll(input.deltaY, precise: input.isPrecise, at: input.point)
            return
        }
        guard input.deltaX != 0 || input.deltaY != 0 else { return }
        userAdjusted = true
        pan = CGSize(
            width: pan.width + input.deltaX,
            height: pan.height + input.deltaY
        )
        panStart = pan
    }

    /// 滚轮缩放，锚在光标下：光标指的模型点保持不动。
    private func zoomByScroll(_ delta: CGFloat, precise: Bool, at point: CGPoint) {
        guard delta != 0 else { return }
        let factor = precise ? pow(1.0025, delta) : pow(1.12, delta)
        let target = min(3, max(0.2, zoom * factor))
        guard target != zoom else { return }
        userAdjusted = true
        let ratio = target / zoom
        pan = CGSize(
            width: point.x - (point.x - pan.width) * ratio,
            height: point.y - (point.y - pan.height) * ratio
        )
        panStart = pan
        zoom = target
        zoomStart = target
    }

    /// 光标落在哪条线上。命中半径按缩放换算，视觉上始终是 12pt 左右。
    private func nearestEdge(
        to point: CGPoint,
        points: [NodeID: CanvasPoint],
        rects: [NodeID: CanvasPoint],
        width: CGFloat
    ) -> EdgeID? {
        guard let project = session.project else { return nil }
        let model = CGPoint(x: (point.x - pan.width) / zoom, y: (point.y - pan.height) / zoom)
        let tolerance = 14 / max(zoom, 0.01)
        var best: (EdgeID, CGFloat)?
        let probe = CGRect(
            x: model.x - tolerance,
            y: model.y - tolerance,
            width: tolerance * 2,
            height: tolerance * 2
        )
        let geometries = edgeCache.geometries(project: project, width: width, points: points) { edge, points in
            edgeGeometry(edge, points: points)
        }
        for edge in project.edges {
            guard let rough = edgeRoughBounds(edge, points: points),
                  rough.intersects(probe) else { continue }
            guard let geometry = geometries[edge.id] else { continue }
            var minimum = CGFloat.greatestFiniteMagnitude
            for sample in geometry.samples {
                let dx = sample.x - model.x
                let dy = sample.y - model.y
                minimum = min(minimum, sqrt(dx * dx + dy * dy))
            }
            if minimum < tolerance, minimum < (best?.1 ?? .greatestFiniteMagnitude) {
                best = (edge.id, minimum)
            }
        }
        return best?.0
    }

    private func visibleNodes(
        nodes: [StoryNode],
        points: [NodeID: CanvasPoint],
        visible: CGRect
    ) -> [StoryNode] {
        nodes.filter { node in
            guard let point = points[node.id] else { return false }
            return visible.intersects(CGRect(origin: CGPoint(x: point.x, y: point.y), size: cardSize))
        }
    }

    /// 故事图的可视坐标：3 列蛇形是自动排布的“基准”，显示时按画布宽度展开成更多列。
    ///
    /// 用户手动拖过的卡（坐标不再等于基准）保留自己的位置；其余自动卡跟着宽度走。
    /// 这里只改显示，不改工程里的 canvas 坐标，所以缩放窗口不会产生历史记录。
    private func displayPoints(
        nodes: [StoryNode],
        project: StoryProject?,
        width: CGFloat
    ) -> [NodeID: CanvasPoint] {
        guard let project else { return [:] }
        let all = layoutCache.points(project: project, width: width)
        var points: [NodeID: CanvasPoint] = [:]
        points.reserveCapacity(nodes.count)
        for node in nodes {
            if let point = all[node.id] {
                points[node.id] = point
            }
        }
        return points
    }

    private func selectNode(_ id: NodeID) {
        session.selectedNodeID = id
        session.insertion = nil
    }


    private func fitContent(in size: CGSize, points: [NodeID: CanvasPoint]) {
        lastSize = size
        guard !points.isEmpty, size.width > 240, size.height > 200 else { return }
        let minX = points.values.map(\.x).min() ?? 0
        let maxX = points.values.map(\.x).max() ?? 0
        let minY = points.values.map(\.y).min() ?? 0
        let maxY = points.values.map(\.y).max() ?? 0
        let contentWidth = maxX - minX + cardSize.width
        let contentHeight = maxY - minY + cardSize.height
        let scale = min(1, min((size.width - 80) / contentWidth, (size.height - 80) / contentHeight))
        let appliedScale = min(1, max(0.5, scale))
        zoom = appliedScale
        zoomStart = appliedScale
        pan = CGSize(
            width: -minX * appliedScale + 40,
            height: -minY * appliedScale + 40
        )
        panStart = pan
    }

    // MARK: 布局

    private func boundingRect(points: [NodeID: CanvasPoint], in size: CGSize) -> CGSize {
        guard let maxX = points.values.map(\.x).max(), let maxY = points.values.map(\.y).max() else {
            return CGSize(width: size.width, height: size.height)
        }
        let minX = points.values.map(\.x).min() ?? 0
        let minY = points.values.map(\.y).min() ?? 0
        return CGSize(
            width: max(size.width, maxX - min(minX, 0) + cardSize.width + 200),
            height: max(size.height, maxY - min(minY, 0) + cardSize.height + 200)
        )
    }

    private func visibleModelRect(in size: CGSize) -> CGRect {
        let originX = -pan.width / zoom
        let originY = -pan.height / zoom
        return CGRect(
            x: originX - 160,
            y: originY - 160,
            width: size.width / zoom + 320,
            height: size.height / zoom + 320
        )
    }

    private var canvasControls: some View {
        HStack(spacing: 6) {
            Button {
                userAdjusted = true
                zoom = min(2.5, zoom * 1.25)
                zoomStart = zoom
            } label: { Image(systemName: "plus.magnifyingglass") }
            .help("放大")
            .accessibilityLabel("放大")
            Button {
                userAdjusted = true
                zoom = max(0.3, zoom / 1.25)
                zoomStart = zoom
            } label: { Image(systemName: "minus.magnifyingglass") }
            .help("缩小")
            .accessibilityLabel("缩小")
            Button {
                userAdjusted = true
                zoom = 1
                zoomStart = 1
                pan = .zero
                panStart = .zero
            } label: { Image(systemName: "1.magnifyingglass") }
            .help("回到 100%")
            .accessibilityLabel("回到 100%")
            Button {
                userAdjusted = false
                if let project = session.project {
                    let nodes = project.nodes.filter { $0.status == .draft }
                    let points = displayPoints(nodes: nodes, project: project, width: lastSize.width)
                    fitContent(in: lastSize, points: points)
                }
            } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
            .help("适应窗口")
            .accessibilityLabel("适应窗口")
        }
        .buttonStyle(.bordered)
        .padding(12)
    }
}
