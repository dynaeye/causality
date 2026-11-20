import CausalityCore
import SwiftUI

/// 脉络画布：卡片按保存的位置摆放，没摆过的先围成一圈。
struct MindMapGraphView: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession
    let graph: CharacterGraph
    /// 右侧人物编辑卡占掉多少宽度：卡片与连线都要让开它。
    var trailingInset: CGFloat = 0
    /// 右栏浮层的宽度：滚轮落在它下面时交回面板。
    var inspectorWidth: CGFloat = 0
    @Binding var focused: CharacterID?

    @State private var cardHeights: [CharacterID: CGFloat] = [:]
    @State private var selectedLink: CharacterGraphLink.ID?
    @State private var selectedKin: CharacterKinLink.ID?
    @State private var hovered: HoverTarget?
    @State private var dragging: CharacterID?
    @State private var dragTranslation: CGSize = .zero
    /// 按下那一刻卡片的位置。拖动期间卡片会跟着手指偏移，不能拿偏移后的位置再算一遍。
    @State private var dragBase: CGPoint?
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize = .zero

    private let cardWidth: CGFloat = 210

    var body: some View {
        GeometryReader { proxy in
            let rects = layout(in: proxy.size)
            ZStack(alignment: .topLeading) {
                theme.background
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedLink = nil
                        selectedKin = nil
                        focused = nil
                    }
                    .gesture(panGesture)
                    .contextMenu {
                        Button("新增人物") { addCharacter(at: proxy.size) }
                    }

                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        drawCoPresence(links: graph.coPresenceLinks, rects: rects, in: &context)
                        drawKinships(rects: rects, in: &context)
                        drawCausal(links: graph.links, rects: rects, in: &context)
                    }
                    .allowsHitTesting(false)

                    ForEach(graph.links) { link in
                        if let hit = linkPath(link, rects: rects) {
                            LinkHitArea(path: hit)
                                .onTapGesture {
                                    selectedLink = selectedLink == link.id ? nil : link.id
                                    selectedKin = nil
                                }
                        }
                    }

                    ForEach(graph.kinships) { kin in
                        if let hit = kinPath(kin, rects: rects) {
                            LinkHitArea(path: hit)
                                .onTapGesture {
                                    selectedKin = selectedKin == kin.id ? nil : kin.id
                                    selectedLink = nil
                                }
                        }
                    }

                    ForEach(graph.nodes) { node in
                        if let rect = rects[node.id] {
                            CharacterCardView(
                                node: node,
                                isFocused: focused == nil || focused == node.id,
                                isSelected: focused == node.id,
                                width: cardWidth,
                                onMeasure: { height in
                                    if abs((cardHeights[node.id] ?? 0) - height) > 0.5 {
                                        cardHeights[node.id] = height
                                    }
                                }
                            )
                            .position(x: rect.midX, y: rect.midY)
                            .gesture(dragGesture(for: node, base: rect.origin))
                        }
                    }

                    if graph.nodes.isEmpty {
                        ContentUnavailableView(
                            "还没有人物",
                            systemImage: "person.2",
                            description: Text("点左上角的 + 添加人物，或在场景详情里给场景加人")
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .coordinateSpace(name: "characterCanvas")
                .scaleEffect(zoom, anchor: .topLeading)
                .offset(pan)
            }
            .overlay(alignment: .bottomLeading) {
                legend
                    .padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                CanvasScrollHint().padding(.bottom, 44)
                zoomControls(in: proxy.size, rects: rects)
                    .padding(12)
            }
            .background(
                ScrollWheelReader(onScroll: { input in
                    handleScroll(input)
                }, trailingCover: inspectorWidth)
            )

            .onAppear { fitContent(in: proxy.size) }
            .onChange(of: proxy.size) { _, newSize in
                // 窗口或栏宽变化时只动视图变换（缩放 + 平移），卡片坐标一概不碰。
                fitContent(in: newSize)
            }
            .onContinuousHover { phase in
                switch phase {
                case let .active(point):
                    hovered = hoverTarget(at: point, rects: rects)
                case .ended:
                    hovered = nil
                }
            }
        }
        .clipped()
    }

    // MARK: 拖拽

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                pan = CGSize(
                    width: panStart.width + value.translation.width,
                    height: panStart.height + value.translation.height
                )
            }
            .onEnded { _ in panStart = pan }
    }

    /// 与场景图一致：滚轮平移，⌘ / ⌥ + 滚轮缩放。
    private func handleScroll(_ input: ScrollWheelInput) {
        if input.isZoom {
            zoomByScroll(input.deltaY, precise: input.isPrecise, at: input.point)
            return
        }
        guard input.deltaX != 0 || input.deltaY != 0 else { return }
        pan = CGSize(
            width: pan.width + input.deltaX,
            height: pan.height + input.deltaY
        )
        panStart = pan
    }

    /// 缩放时锚在光标下。
    private func zoomByScroll(_ delta: CGFloat, precise: Bool, at point: CGPoint) {
        guard delta != 0 else { return }
        let factor = precise ? pow(1.0025, delta) : pow(1.12, delta)
        let target = min(3, max(0.2, zoom * factor))
        guard target != zoom else { return }
        let ratio = target / zoom
        pan = CGSize(
            width: point.x - (point.x - pan.width) * ratio,
            height: point.y - (point.y - pan.height) * ratio
        )
        panStart = pan
        zoom = target
        zoomStart = target
    }

    private func zoomControls(in size: CGSize, rects: [CharacterID: CGRect]) -> some View {
        HStack(spacing: 6) {
            Button {
                zoom = min(3, zoom * 1.25)
                zoomStart = zoom
            } label: { Image(systemName: "plus.magnifyingglass") }
            .help("放大")
            .accessibilityLabel("放大")
            Button {
                zoom = max(0.2, zoom / 1.25)
                zoomStart = zoom
            } label: { Image(systemName: "minus.magnifyingglass") }
            .help("缩小")
            .accessibilityLabel("缩小")
            Button {
                fit(rects: rects, in: size)
            } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
            .help("适应窗口")
            .accessibilityLabel("适应窗口")
        }
        .buttonStyle(.bordered)
    }

    private func fit(rects: [CharacterID: CGRect], in size: CGSize) {
        guard !rects.isEmpty else { return }
        let union = rects.values.reduce(rects.values.first!) { $0.union($1) }
        guard union.width > 0, union.height > 0 else { return }
        let scale = min(1, min((size.width - 80) / union.width, (size.height - 120) / union.height))
        let appliedScale = max(0.3, scale)
        zoom = appliedScale
        zoomStart = appliedScale
        pan = CGSize(
            width: -union.minX * appliedScale + 40,
            height: -union.minY * appliedScale + 40
        )
        panStart = pan
    }

    /// 点按与拖动共用一个手势：位移小于 4pt 当点选，超过才移动卡片。
    /// 分成两个手势时，macOS 上的拖拽会把点按吃掉。
    private func dragGesture(for node: CharacterGraphNode, base: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("characterCanvas"))
            .onChanged { value in
                if dragging != node.id {
                    dragging = node.id
                    dragBase = base
                    selectedLink = nil
                    focused = node.id
                }
                dragTranslation = value.translation
            }
            .onEnded { value in
                let start = dragBase
                defer {
                    dragging = nil
                    dragTranslation = .zero
                    dragBase = nil
                }
                let distance = abs(value.translation.width) + abs(value.translation.height)
                if distance < 4 {
                    // 跟左侧列表一致：点已选中的那张卡再点一下收起编辑层。
                    focused = focused == node.id ? nil : node.id
                    return
                }
                // 起点取按下那一刻的位置：拖动时卡片已经跟着位移，再拿它当基准会多走一倍。
                guard let start else { return }
                let target = CanvasLayout.dragged(
                    from: CanvasPoint(x: start.x, y: start.y),
                    dx: value.translation.width,
                    dy: value.translation.height,
                    zoom: zoom
                )
                session.moveCharacter(node.id, to: target)
            }
    }

    // MARK: 布局

    private func addCharacter(at size: CGSize) {
        let id = session.addCharacter()
        let point = CanvasPoint(
            x: max(0, size.width / 2 - cardWidth / 2),
            y: max(0, size.height / 2 - 60)
        )
        session.moveCharacter(id, to: point)
        focused = id
    }



    /// 把所有卡片装进当前可视区：只调 zoom 与 pan，不改模型坐标。
    private func fitContent(in size: CGSize) {
        let nodes = graph.nodes
        guard !nodes.isEmpty, size.width > 40, size.height > 40 else { return }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for node in nodes {
            guard let point = basePoint(for: node.id) else { continue }
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x + cardWidth)
            maxY = max(maxY, point.y + height(of: node))
        }
        guard minX.isFinite, maxX > minX else { return }

        let margin: CGFloat = 24
        let width = size.width - trailingInset - margin * 2
        let height = size.height - margin * 2
        guard width > 20, height > 20 else { return }

        let fit = min(width / (maxX - minX), height / (maxY - minY), 1)
        let nextZoom = max(0.3, fit)
        let left = (size.width - trailingInset - (maxX - minX) * nextZoom) / 2
        let top = (size.height - (maxY - minY) * nextZoom) / 2

        zoom = nextZoom
        zoomStart = nextZoom
        pan = CGSize(width: left - minX * nextZoom, height: top - minY * nextZoom)
        panStart = pan
    }

    private func basePoint(for id: CharacterID) -> CGPoint? {
        session.characterPoint(for: id).map { CGPoint(x: $0.x, y: $0.y) }
    }

    private func layout(in size: CGSize) -> [CharacterID: CGRect] {
        let nodes = graph.nodes
        guard !nodes.isEmpty else { return [:] }

        var result: [CharacterID: CGRect] = [:]
        var pending: [CharacterGraphNode] = []

        for node in nodes {
            if let stored = basePoint(for: node.id) {
                result[node.id] = CGRect(origin: stored, size: CGSize(width: cardWidth, height: height(of: node)))
            } else {
                pending.append(node)
            }
        }

        if !pending.isEmpty {
            let center = CGPoint(x: (size.width - trailingInset) / 2, y: size.height / 2)
            let radius: CGFloat = min(
                max(150, (size.width - trailingInset) / 2 - cardWidth / 2 - 30),
                max(150, size.height / 2 - 90)
            )
            let step: CGFloat = 2 * .pi / CGFloat(max(pending.count, 1))
            for (offset, node) in pending.enumerated() {
                let angle: CGFloat = CGFloat(offset) * step - .pi / 2
                let cosAngle = CGFloat(cos(Double(angle)))
                let sinAngle = CGFloat(sin(Double(angle)))
                let cardHeight = height(of: node)
                let x = center.x + radius * cosAngle - cardWidth / 2
                let y = center.y + radius * sinAngle - cardHeight / 2
                result[node.id] = CGRect(x: x, y: y, width: cardWidth, height: cardHeight)
            }
        }

        if let dragging, let rect = result[dragging] {
            result[dragging] = rect.offsetBy(dx: dragTranslation.width / zoom, dy: dragTranslation.height / zoom)
        }

        // 卡片位置只由模型决定：编辑栏浮在上层，画布宽度不变，
        // 打开面板不该让任何一张卡换位置。
        return result
    }

    private func height(of node: CharacterGraphNode) -> CGFloat {
        cardHeights[node.id] ?? 96
    }

    // MARK: 连线

    /// 同场共现：实线，权重就是共现场数。
    private func drawCoPresence(
        links: [CharacterCoPresenceLink],
        rects: [CharacterID: CGRect],
        in context: inout GraphicsContext
    ) {
        for link in links {
            guard let from = rects[link.from], let to = rects[link.to],
                  let geometry = curve(from: from, to: to) else { continue }
            let dimmed = focused != nil && focused != link.from && focused != link.to
            let color = theme.textSecondary.opacity(dimmed ? 0.12 : 0.55)
            var path = Path()
            path.move(to: geometry.start)
            path.addQuadCurve(to: geometry.end, control: geometry.control)
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.0 + CGFloat(min(link.weight, 4)) * 0.55)
            )
        }
    }

    /// 因果层：虚线、40% 不透明度，和同场实线分开。
    private func drawCausal(
        links: [CharacterGraphLink],
        rects: [CharacterID: CGRect],
        in context: inout GraphicsContext
    ) {
        for link in links {
            guard let from = rects[link.from], let to = rects[link.to],
                  let geometry = curve(from: from, to: to) else { continue }

            let dimmed = focused != nil && focused != link.from && focused != link.to
            let isSelected = selectedLink == link.id
            let isHovered = hovered?.id == link.id && hovered?.isKin == false
            let color = theme.lineColor(for: link.kind)
                .opacity(isSelected || isHovered ? 0.95 : (dimmed ? 0.08 : 0.4))

            var path = Path()
            path.move(to: geometry.start)
            path.addQuadCurve(to: geometry.end, control: geometry.control)
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(
                    lineWidth: (isSelected || isHovered) ? 2.0 : 1.0,
                    dash: [4, 4]
                )
            )

            let dx = geometry.end.x - geometry.control.x
            let dy = geometry.end.y - geometry.control.y
            let length = max(sqrt(dx * dx + dy * dy), 0.01)
            let unit = CGPoint(x: dx / length, y: dy / length)
            let tip = CGPoint(x: geometry.end.x - unit.x * 8, y: geometry.end.y - unit.y * 8)
            var arrow = Path()
            arrow.move(to: CGPoint(x: tip.x - unit.y * 4, y: tip.y + unit.x * 4))
            arrow.addLine(to: CGPoint(x: tip.x + unit.x * 6, y: tip.y + unit.y * 6))
            arrow.addLine(to: CGPoint(x: tip.x + unit.y * 4, y: tip.y - unit.x * 4))
            context.stroke(arrow, with: .color(color), lineWidth: 1.2)

        }
    }

    /// 亲属/亲友线：虚线、不加箭头，和因果线区分开。
    private func drawKinships(rects: [CharacterID: CGRect], in context: inout GraphicsContext) {
        for kin in graph.kinships {
            guard let from = rects[kin.from], let to = rects[kin.to],
                  let geometry = kinCurve(from: from, to: to) else { continue }
            let dimmed = focused != nil && focused != kin.from && focused != kin.to
            let isSelected = selectedKin == kin.id
            let isHovered = hovered?.id == kin.id && hovered?.isKin == true
            let color = theme.textSecondary.opacity(isSelected || isHovered ? 0.95 : (dimmed ? 0.12 : 0.55))

            var path = Path()
            path.move(to: geometry.start)
            path.addQuadCurve(to: geometry.end, control: geometry.control)
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: (isSelected || isHovered) ? 2.2 : 1.2, dash: [5, 4])
            )

            if isSelected || isHovered {
                context.draw(
                    Text(kin.label)
                        .font(theme.fontMin)
                        .foregroundStyle(theme.textPrimary),
                    at: geometry.labelPoint,
                    anchor: .center
                )
            }
        }
    }

    private func kinPath(_ kin: CharacterKinLink, rects: [CharacterID: CGRect]) -> Path? {
        guard let from = rects[kin.from], let to = rects[kin.to],
              let geometry = kinCurve(from: from, to: to) else { return nil }
        var path = Path()
        path.move(to: geometry.start)
        path.addQuadCurve(to: geometry.end, control: geometry.control)
        return path
    }

    private func kinCurve(from: CGRect, to: CGRect) -> CurveGeometry? {
        guard let geometry = curve(from: from, to: to) else { return nil }
        // 与因果线错开，避免同一对人物两条线重叠。
        let midX = (geometry.start.x + geometry.end.x) / 2
        let midY = (geometry.start.y + geometry.end.y) / 2
        let sway = min(40, max(20, abs(geometry.start.x - geometry.end.x) * 0.14))
        let control = CGPoint(x: midX, y: midY + sway)
        let labelPoint = CGPoint(
            x: 0.25 * geometry.start.x + 0.5 * control.x + 0.25 * geometry.end.x,
            y: 0.25 * geometry.start.y + 0.5 * control.y + 0.25 * geometry.end.y
        )
        return CurveGeometry(start: geometry.start, end: geometry.end, control: control, labelPoint: labelPoint)
    }

    struct HoverTarget: Equatable {
        var id: String
        var isKin: Bool
    }

    private func hoverTarget(at point: CGPoint, rects: [CharacterID: CGRect]) -> HoverTarget? {
        let model = CGPoint(x: (point.x - pan.width) / zoom, y: (point.y - pan.height) / zoom)
        let tolerance = 14 / max(zoom, 0.01)
        var best: (HoverTarget, CGFloat)?

        func consider(_ id: String, _ isKin: Bool, _ geometry: CurveGeometry) {
            var minimum = CGFloat.greatestFiniteMagnitude
            for step in 0 ... 16 {
                let t = CGFloat(step) / 16
                let inverse = 1 - t
                let sample = CGPoint(
                    x: inverse * inverse * geometry.start.x + 2 * inverse * t * geometry.control.x + t * t * geometry.end.x,
                    y: inverse * inverse * geometry.start.y + 2 * inverse * t * geometry.control.y + t * t * geometry.end.y
                )
                let dx = sample.x - model.x
                let dy = sample.y - model.y
                minimum = min(minimum, sqrt(dx * dx + dy * dy))
            }
            guard minimum < tolerance else { return }
            if minimum < (best?.1 ?? .greatestFiniteMagnitude) {
                best = (HoverTarget(id: id, isKin: isKin), minimum)
            }
        }

        for link in graph.links {
            guard let from = rects[link.from], let to = rects[link.to],
                  let geometry = curve(from: from, to: to) else { continue }
            consider(link.id, false, geometry)
        }
        for kin in graph.kinships {
            guard let from = rects[kin.from], let to = rects[kin.to],
                  let geometry = kinCurve(from: from, to: to) else { continue }
            consider(kin.id, true, geometry)
        }

        return best?.0
    }

    private struct CurveGeometry {
        var start: CGPoint
        var end: CGPoint
        var control: CGPoint
        var labelPoint: CGPoint
    }

    /// 从卡片边框出线，卡片多高都贴着边走。
    private func curve(from: CGRect, to: CGRect) -> CurveGeometry? {
        let fromCenter = CGPoint(x: from.midX, y: from.midY)
        let toCenter = CGPoint(x: to.midX, y: to.midY)
        guard fromCenter != toCenter else { return nil }
        let start = borderPoint(in: from, toward: toCenter)
        let end = borderPoint(in: to, toward: fromCenter)
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        let sway = min(36, max(18, abs(start.x - end.x) * 0.12))
        let control = CGPoint(x: midX, y: midY - sway)
        let labelPoint = CGPoint(
            x: 0.25 * start.x + 0.5 * control.x + 0.25 * end.x,
            y: 0.25 * start.y + 0.5 * control.y + 0.25 * end.y
        )
        return CurveGeometry(start: start, end: end, control: control, labelPoint: labelPoint)
    }

    private func borderPoint(in rect: CGRect, toward target: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = target.x - center.x
        let dy = target.y - center.y
        guard dx != 0 || dy != 0 else { return center }
        let halfWidth = rect.width / 2
        let halfHeight = rect.height / 2
        let scaleX = dx == 0 ? CGFloat.infinity : halfWidth / abs(dx)
        let scaleY = dy == 0 ? CGFloat.infinity : halfHeight / abs(dy)
        let scale = min(scaleX, scaleY)
        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }

    // MARK: 点击命中与图例

    private func linkPath(_ link: CharacterGraphLink, rects: [CharacterID: CGRect]) -> Path? {
        guard let from = rects[link.from], let to = rects[link.to],
              let geometry = curve(from: from, to: to) else { return nil }
        var path = Path()
        path.move(to: geometry.start)
        path.addQuadCurve(to: geometry.end, control: geometry.control)
        return path
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let selectedKin, let kin = graph.kinships.first(where: { $0.id == selectedKin }) {
                Text(verbatim: String(
                    format: InterfaceLanguage.label("%@（%@）↔ %@（%@）"),
                    name(of: kin.from),
                    InterfaceLanguage.label(kin.kind.displayName),
                    name(of: kin.to),
                    InterfaceLanguage.label(kin.counterpartKind?.displayName ?? kin.kind.reverse.displayName)
                ))
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textPrimary)
                Text("亲属/亲友关系，来自人物详情里的选择")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
            } else if let selectedLink, let link = graph.links.first(where: { $0.id == selectedLink }) {
                Text(verbatim: String(
                    format: InterfaceLanguage.label("%@ → %@｜%@：%@"),
                    name(of: link.from),
                    name(of: link.to),
                    InterfaceLanguage.label(link.kind.displayName),
                    link.label
                ))
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textPrimary)
                Text(verbatim: String(
                    format: InterfaceLanguage.label("来自：%@%@"),
                    link.viaTitles,
                    link.weight > 1 ? String(format: InterfaceLanguage.label("（同因 %lld 处）"), link.weight) : ""
                ))
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
            } else {
                Text("实线是同场共现（越粗同场越多），虚线是因果与亲属/亲友；点线在左下角看说明，卡片可以拖动。")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(10)
        .background(theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.border, lineWidth: 1)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func name(of id: CharacterID) -> String {
        graph.nodes.first { $0.id == id }?.character.name ?? "?"
    }
}

/// 透明的命中层：同样的曲线，加粗到 16pt 才好点。
struct LinkHitArea: View {
    let path: Path

    var body: some View {
        path
            .stroke(Color.clear, lineWidth: 1)
            .contentShape(path.strokedPath(StrokeStyle(lineWidth: 16)))
    }
}
