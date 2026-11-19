import CausalityCore
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "causal.appearance"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum ColorPreset: String, CaseIterable, Identifiable {
    case warmPaper
    case softGray
    case nord
    case gruvbox
    case softInk
    case catppuccin
    case solarized
    case mossGarden
    case rainSlate
    case lotusHaze
    case apricotLetter
    case seaGlass
    case terracotta
    case mistPine
    case quartz
    case indigoPaper
    case hushedHoney
    case moonlit
    case mountainVeil
    case bambooInk

    static let storageKey = "causal.colorPreset"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .warmPaper: "暖纸"
        case .softGray: "柔灰"
        case .nord: "北境"
        case .gruvbox: "旧时光"
        case .softInk: "柔墨"
        case .catppuccin: "猫奶油"
        case .solarized: "日蚀"
        case .mossGarden: "苔庭"
        case .rainSlate: "雨青"
        case .lotusHaze: "藕烟"
        case .apricotLetter: "杏笺"
        case .seaGlass: "海盐"
        case .terracotta: "赤陶"
        case .mistPine: "雾杉"
        case .quartz: "石英"
        case .indigoPaper: "靛笺"
        case .hushedHoney: "蜂蜜"
        case .moonlit: "月白"
        case .mountainVeil: "山岚"
        case .bambooInk: "竹影"
        }
    }

    var detail: String {
        switch self {
        case .warmPaper: "书页、羊皮纸；暖炭旧书封"
        case .softGray: "中性灰阶；石墨安静"
        case .nord: "冷雾北境；极夜冰蓝"
        case .gruvbox: "麦纸复古；深褐暖墨"
        case .softInk: "淡墨留白；墨室微光"
        case .catppuccin: "柔和彩色；紫灰夜色"
        case .solarized: "米金青灰；深海青灰"
        case .mossGarden: "苔绿自然；松影深林"
        case .rainSlate: "雨幕青石；暮雨蓝灰"
        case .lotusHaze: "藕白淡紫；烟紫夜雾"
        case .apricotLetter: "杏纸暖灰；栗壳柔金"
        case .seaGlass: "海盐白浅青；深湾玻璃蓝"
        case .terracotta: "陶土亚麻；赤陶夜色"
        case .mistPine: "松雾青灰；雾杉深青"
        case .quartz: "粉灰浅石；紫石深灰"
        case .indigoPaper: "蓝白纸感；靛青墨夜"
        case .hushedHoney: "蜜蜡暖纸；蜂蜜棕深夜"
        case .moonlit: "月白冷灰；月夜银灰"
        case .mountainVeil: "岩灰天光；山影石墨蓝"
        case .bambooInk: "竹纸青墨；竹影深绿"
        }
    }

    func theme(isDark: Bool) -> Theme {
        switch self {
        case .warmPaper: isDark ? .warmPaperDark : .warmPaperLight
        case .softGray: isDark ? .softGrayDark : .softGrayLight
        case .nord: isDark ? .nordDark : .nordLight
        case .gruvbox: isDark ? .gruvboxDark : .gruvboxLight
        case .softInk: isDark ? .softInkDark : .softInkLight
        case .catppuccin: isDark ? .catppuccinDark : .catppuccinLight
        case .solarized: isDark ? .solarizedDark : .solarizedLight
        case .mossGarden: isDark ? .mossGardenDark : .mossGardenLight
        case .rainSlate: isDark ? .rainSlateDark : .rainSlateLight
        case .lotusHaze: isDark ? .lotusHazeDark : .lotusHazeLight
        case .apricotLetter: isDark ? .apricotLetterDark : .apricotLetterLight
        case .seaGlass: isDark ? .seaGlassDark : .seaGlassLight
        case .terracotta: isDark ? .terracottaDark : .terracottaLight
        case .mistPine: isDark ? .mistPineDark : .mistPineLight
        case .quartz: isDark ? .quartzDark : .quartzLight
        case .indigoPaper: isDark ? .indigoPaperDark : .indigoPaperLight
        case .hushedHoney: isDark ? .hushedHoneyDark : .hushedHoneyLight
        case .moonlit: isDark ? .moonlitDark : .moonlitLight
        case .mountainVeil: isDark ? .mountainVeilDark : .mountainVeilLight
        case .bambooInk: isDark ? .bambooInkDark : .bambooInkLight
        }
    }
}

/// 一套配色的语义槽位。背景偏暖或偏灰，文字用柔和灰阶，关系线与边框保持低对比。
struct Theme: Equatable {
    let isDark: Bool

    /// 主背景：故事板底板。
    let background: Color
    /// 最底层：侧栏。
    let deep: Color
    /// 面板：章节列、分组容器。
    let surface: Color
    /// 抬升层：卡片、输入框。
    let surfaceRaised: Color
    /// 图片容器。略不同於卡片，让图片自己发光。
    let imageWell: Color

    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    /// 低对比细线与分隔。
    let border: Color
    let borderStrong: Color

    let accent: Color
    let accentSoft: Color
    /// 念头、未接线这类“还没定”的状态。
    let warning: Color
    let ending: Color
    let choice: Color
    let condition: Color
    let neutralLine: Color

    func lineColor(for kind: EdgeKind) -> Color {
        switch kind {
        case .cause: accent
        case .choice: choice
        case .condition: condition
        case .plain: textTertiary
        }
    }

    func kindColor(for kind: NodeKind) -> Color {
        switch kind {
        case .event: accent
        case .choice: choice
        case .ending: ending
        }
    }

    static func resolve(_ mode: AppearanceMode, system: ColorScheme, preset: ColorPreset = .catppuccin) -> Theme {
        let dark: Bool
        switch mode {
        case .system: dark = system == .dark
        case .light: dark = false
        case .dark: dark = true
        }
        return preset.theme(isDark: dark)
    }
}

// MARK: - 字号

extension Theme {
    /// 正文默认 16 号，界面上最小 14 号。
    static let bodySize: CGFloat = 16
    static let minSize: CGFloat = 14

    var fontBody: Font { .system(size: Self.bodySize) }
    var fontBodyMedium: Font { .system(size: Self.bodySize, weight: .medium) }
    var fontMin: Font { .system(size: Self.minSize) }
    var fontMinBold: Font { .system(size: Self.minSize, weight: .semibold) }
    var fontCardTitle: Font { .system(size: 17, weight: .semibold) }
    var fontTitle: Font { .system(size: 20, weight: .semibold) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.latte
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - 设置

@MainActor
enum AppearanceController {
    static func apply(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// 设置里的外观选项：两个下拉框，一组跟随方案变化的预览。
struct AppearanceSettingsView: View {
    @AppStorage(InterfaceLanguage.storageKey) private var language = InterfaceLanguage.system
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(ColorPreset.storageKey) private var preset = ColorPreset.catppuccin.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @State private var needsRestart = InterfaceLanguage.bundleNeedsRestart

    private var mode: AppearanceMode { AppearanceMode(rawValue: appearance) ?? .system }
    private var colorPreset: ColorPreset { ColorPreset(rawValue: preset) ?? .catppuccin }
    private var theme: Theme { Theme.resolve(mode, system: colorScheme, preset: colorPreset) }

    var body: some View {
        Form {
            Section {
                Picker("界面语言", selection: $language) {
                    ForEach(InterfaceLanguage.allCases, id: \.self) { option in
                        Text(verbatim: option == .system ? language.label("跟随系统") : option.name).tag(option)
                    }
                }
                .onChange(of: language) { _, newValue in
                    newValue.applyBundleLanguage()
                    needsRestart = true
                }
                if needsRestart {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("菜单栏与「关于」会在重启后换语言。")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                        Button("现在重启") { InterfaceLanguage.relaunch() }
                            .controlSize(.small)
                    }
                }
                Picker("外观", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { option in
                        Text(LocalizedStringKey(option.displayName)).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Picker("配色方案", selection: $preset) {
                    ForEach(ColorPreset.allCases) { option in
                        Text(LocalizedStringKey(option.displayName)).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(LocalizedStringKey(colorPreset.detail))
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)

                if mode == .system {
                    Text(LocalizedStringKey(colorScheme == .dark ? "系统当前：深色" : "系统当前：浅色"))
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)
                }
            } header: {
                Text("配色")
            } footer: {
                Text("浅色不用纯白，深色不用纯黑；关系线与边框保持低对比。20 套方案各带浅深两版。")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }

            Section("预览") {
                ThemePreview(theme: theme, title: InterfaceLanguage.label("第一章"), presetName: colorPreset.displayName)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.vertical, 8)
        .background(theme.background)
    }
}

/// 一小块故事板：底板、列、卡、正文、关系线与强调色，全部来自当前主题。
struct ThemePreview: View {
    let theme: Theme
    let title: String
    let presetName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                column
                column.opacity(0.85)
            }
            HStack(spacing: 10) {
                swatch(theme.background, "底板")
                swatch(theme.surface, "面板")
                swatch(theme.surfaceRaised, "卡片")
                swatch(theme.accent, "强调")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Text(LocalizedStringKey(presetName))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .padding(.trailing, 4)
                .padding(.top, 4)
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            card("她是怎么认出母亲笔迹的？", "灯底的笔画歪了一下。", accent: theme.warning)
            card("梁婆婆认出河灯", "她说这灯是她扎的。", accent: nil)
            HStack(spacing: 4) {
                Rectangle()
                    .fill(theme.accent.opacity(0.8))
                    .frame(width: 18, height: 1.4)
                Circle()
                    .fill(theme.accent)
                    .frame(width: 4, height: 4)
                Text("因为")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.accent)
                Spacer()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.border, lineWidth: 1)
        }
    }

    private func card(_ title: String, _ body: String, accent: Color?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let accent {
                    Text("念头")
                        .font(.system(size: 8))
                        .padding(.horizontal, 3)
                        .background(accent.opacity(0.18), in: Capsule())
                        .foregroundStyle(accent)
                }
                Text(LocalizedStringKey(title))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
            }
            Text(LocalizedStringKey(body))
                .font(.system(size: 9))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(theme.border, lineWidth: 1)
        }
    }

    private func swatch(_ color: Color, _ title: String) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color)
                .frame(height: 22)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                }
            Text(LocalizedStringKey(title))
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

