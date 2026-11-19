import Foundation
import Testing
@testable import CausalityCore

@Suite("卡片拖动落点")
struct CanvasDragTests {
    @Test("1 倍时落点就是起点加位移")
    func plainDrag() {
        let target = CanvasLayout.dragged(from: CanvasPoint(x: 100, y: 80), dx: 200, dy: -30, zoom: 1)
        #expect(target.x == 300)
        #expect(target.y == 50)
    }

    @Test("放大后位移要除以缩放")
    func zoomedDrag() {
        let target = CanvasLayout.dragged(from: CanvasPoint(x: 100, y: 100), dx: 200, dy: 100, zoom: 2)
        #expect(target.x == 200)
        #expect(target.y == 150)
    }

    @Test("缩小后位移放大")
    func zoomedOutDrag() {
        let target = CanvasLayout.dragged(from: CanvasPoint(x: 40, y: 40), dx: 100, dy: 100, zoom: 0.5)
        #expect(target.x == 240)
        #expect(target.y == 240)
    }

    @Test("不会拖到负坐标")
    func clampsAtOrigin() {
        let target = CanvasLayout.dragged(from: CanvasPoint(x: 10, y: 10), dx: -200, dy: -200, zoom: 1)
        #expect(target.x == 0)
        #expect(target.y == 0)
    }

    @Test("缩放为 0 时按 1 处理，不出现除零")
    func zeroZoomFallsBack() {
        let target = CanvasLayout.dragged(from: CanvasPoint(x: 5, y: 5), dx: 10, dy: 10, zoom: 0)
        #expect(target.x == 15)
        #expect(target.y == 15)
    }
}
