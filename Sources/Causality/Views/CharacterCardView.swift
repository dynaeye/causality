import CausalityCore
import SwiftUI

/// 人物卡。高度由内容决定，外框跟着文字长。
struct CharacterCardView: View {
    @Environment(\.theme) private var theme
    let node: CharacterGraphNode
    let isFocused: Bool
    let isSelected: Bool
    let width: CGFloat
    let onMeasure: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: node.character.name.isEmpty ? InterfaceLanguage.label("未命名人物") : node.character.name)
                .font(theme.fontCardTitle)
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !node.character.summary.isEmpty {
                Text(node.character.summary)
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if node.hasAppeared == false {
                Text("还没出场，点开写点介绍")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
            }

            HStack(spacing: 8) {
                Text(node.hasAppeared ? LocalizedStringKey(String(format: InterfaceLanguage.label("出场 %lld"), node.sceneCount)) : LocalizedStringKey("未出场"))
                    .foregroundStyle(node.hasAppeared ? theme.textTertiary : theme.warning)
                if node.selfAdvanceCount > 0 {
                    Text(String(format: InterfaceLanguage.label("自身推进 %lld"), node.selfAdvanceCount))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .font(theme.fontMin)
        }
        .padding(10)
        .frame(width: width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 2 : 1)
        }
        .opacity(isFocused ? 1 : 0.45)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onMeasure(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, newValue in onMeasure(newValue) }
            }
        )
    }
}
