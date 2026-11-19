import SwiftUI

/// 品牌字标。中文、日文、繁体用「因」「果」两字；英文用 Causality。
struct BrandWordmark: View {
    var size: CGFloat

    var body: some View {
        let word = InterfaceLanguage.label("因果")
        Group {
            if word.count <= 2 {
                HStack(spacing: size * 0.26) {
                    Text("因")
                    Text("果")
                }
            } else {
                Text(verbatim: word)
            }
        }
        .font(.system(size: word.count <= 2 ? size : size * 0.72, weight: .semibold))
    }
}
