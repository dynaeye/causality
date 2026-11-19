import SwiftUI

/// 右栏的一段。折叠时只留标题与一行摘要，状态存在 AppStorage，重开还在。
struct InspectorSection<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    /// 折叠时显示的摘要。空字符串就只留标题。
    let hint: String
    @Binding var collapsed: Bool
    let content: Content

    init(
        title: String,
        hint: String = "",
        collapsed: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.hint = hint
        self._collapsed = collapsed
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    collapsed.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                    Text(LocalizedStringKey(title))
                        .font(theme.fontMinBold)
                        .foregroundStyle(theme.textSecondary)
                    if collapsed, !hint.isEmpty {
                        Text(hint)
                            .font(theme.fontMin)
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(collapsed ? "展开「\(title)」" : "收起「\(title)」")

            if !collapsed {
                content
                    .padding(.bottom, 8)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.border.opacity(0.7))
                .frame(height: 1)
        }
    }
}
