import AppKit
import SwiftUI

/// 顶栏下面那条横线由内容区自己画（`PaneTopRule`），所以先把系统画的那条关掉，
/// 免得故事板、大纲这两处原本有线的视图变成两像素。
struct TitlebarSeparator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.titlebarSeparatorStyle = .none
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if nsView.window?.titlebarSeparatorStyle != .none {
                nsView.window?.titlebarSeparatorStyle = .none
            }
        }
    }
}

/// 中栏顶部的一条线：四个视图（故事板 / 大纲 / 人物脉络 / 故事图）都从这条线下面开始。
struct PaneTopRule: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.border)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}
