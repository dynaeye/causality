import AppKit
import SwiftUI

/// 把画布区域的滚轮事件收上来。
///
/// SwiftUI 没有滚轮回调，这里用一个本地事件监听：只有光标落在自己范围内才消费，
/// 其余滚轮照常交给系统。
struct ScrollWheelInput {
    var deltaX: CGFloat
    var deltaY: CGFloat
    /// 触控板的两指滚动，量小且连续。
    var isPrecise: Bool
    /// ⌘ 或 ⌥ 按住时是缩放，否则是平移。
    var isZoom: Bool
    /// 光标在本视图内的位置。
    var point: CGPoint
}

struct ScrollWheelReader: NSViewRepresentable {
    var onScroll: (ScrollWheelInput) -> Void
    /// 右栏浮层盖住的宽度。落在这一带里的滚轮要让回浮层自己的滚动视图，
    /// 否则在故事图 / 人物关系里滚详情面板会变成平移画布。
    var trailingCover: CGFloat = 0

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onScroll = onScroll
        view.trailingCover = trailingCover
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onScroll = onScroll
        nsView.trailingCover = trailingCover
    }

    final class TrackingView: NSView {
        var onScroll: ((ScrollWheelInput) -> Void)?
        var trailingCover: CGFloat = 0
        private var monitor: Any?

        /// 只负责收滚轮事件，鼠标点击与拖拽全部让给 SwiftUI，
        /// 否则垫在底下的这个 NSView 会时不时把拖拽吃掉。
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
                return
            }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      let window = self.window,
                      event.window === window,
                      !isHidden else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                guard point.x < self.bounds.maxX - self.trailingCover else { return event }
                let modifiers = event.modifierFlags
                self.onScroll?(ScrollWheelInput(
                    deltaX: event.scrollingDeltaX,
                    deltaY: event.scrollingDeltaY,
                    isPrecise: event.hasPreciseScrollingDeltas,
                    isZoom: modifiers.contains(.command) || modifiers.contains(.option),
                    point: point
                ))
                return nil
            }
        }
    }
}
