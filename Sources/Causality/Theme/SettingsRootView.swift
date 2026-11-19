import SwiftUI

/// 设置窗口：两个纯文字页签，没有图标，也没有系统的悬停高亮。
struct SettingsRootView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage(ColorPreset.storageKey) private var presetRaw = ColorPreset.catppuccin.rawValue
    @State private var tab: SettingsTab = .appearance

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    private var theme: Theme {
        Theme.resolve(
            appearance,
            system: systemColorScheme,
            preset: ColorPreset(rawValue: presetRaw) ?? .catppuccin
        )
    }

    enum SettingsTab: String, CaseIterable, Identifiable {
        case appearance
        case ai
        case cli

        var id: String { rawValue }
        var title: String {
            switch self {
            case .appearance: "外观"
            case .ai: "Agent"
            case .cli: "MCP"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                ForEach(SettingsTab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        Text(LocalizedStringKey(item.title))
                            .font(theme.fontBody)
                            .foregroundStyle(tab == item ? theme.textPrimary : theme.textSecondary)
                            .padding(.vertical, 5)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(tab == item ? theme.accent : Color.clear)
                                    .frame(height: 2)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider().overlay(theme.border)

            switch tab {
            case .appearance:
                AppearanceSettingsView()
            case .ai:
                AISettingsView()
            case .cli:
                CLISettingsView()
            }
        }
        .frame(width: 560, height: 560)
        .background(theme.background)
        .environment(\.theme, theme)
        .onAppear { AppearanceController.apply(appearance) }
        .onChange(of: appearanceRaw) { _, _ in AppearanceController.apply(appearance) }
    }
}
