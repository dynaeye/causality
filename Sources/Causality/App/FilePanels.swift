import AppKit

/// 文件与图片面板统一从这里出。
///
/// 直接在异步任务里 `runModal()` 会另起一个模态循环：App 不是前台时，面板里的「位置」下拉弹不出菜单，
/// 取消按钮也吃不到点击。挂成窗口的 sheet、先把 App 拿到前台，就没有这两个毛病。
@MainActor
enum FilePanels {
    static func url(_ panel: NSSavePanel) async -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = hostWindow() else {
            // 连窗口都没有时只能走老路。
            return panel.runModal() == .OK ? panel.url : nil
        }
        let response = await panel.beginSheetModal(for: window)
        return response == .OK ? panel.url : nil
    }

    private static func hostWindow() -> NSWindow? {
        if let key = NSApp.keyWindow, !(key is NSPanel) { return key }
        if let main = NSApp.mainWindow { return main }
        return NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }
    }
}
