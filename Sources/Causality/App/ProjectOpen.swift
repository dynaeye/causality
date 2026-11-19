import AppKit
import CausalityCore

extension Notification.Name {
    /// 访达双击、拖到 Dock 图标、`open -a 因果 项目.causal` 都从这里进来。
    static let openProject = Notification.Name("Causality.openProject")
}

/// WindowGroup 没有文档模型，系统送来的文件不会自己落进窗口，所以在这里接住再转给界面。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 冷启动时窗口还没建好，先把地址留在这里，视图出现时取走。
    private static var pendingURL: URL?
    private var observers: [NSObjectProtocol] = []

    static func takePendingURL() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: Self.isProject) ?? urls.first else { return }
        Self.pendingURL = url
        NotificationCenter.default.post(name: .openProject, object: url)
    }

    /// 双击工程包时系统还会顺手要求一个空窗口，这里不要再开一个。
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    /// 单窗口工具：关上窗口就退出。关窗前 `windowWillClose` 会先同步存一次盘。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 窗口默认尺寸可能比屏幕还高（比如 16:9 的小本），底部会被屏幕切掉，
        // 详情面板最后几段就永远看不到。建好后按可见区收一次，换屏幕也再收一次。
        DispatchQueue.main.async { Self.fitWindowsToVisibleScreen() }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in Self.fitWindowsToVisibleScreen() }
        })
    }

    private static func fitWindowsToVisibleScreen() {
        for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) {
            guard let screen = window.screen ?? NSScreen.main else { continue }
            let visible = screen.visibleFrame
            var frame = window.frame
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
            if frame != window.frame {
                window.setFrame(frame, display: true)
            }
        }
    }

    private static func isProject(_ url: URL) -> Bool {
        ProjectPackage.isProjectPackage(url)
    }
}
