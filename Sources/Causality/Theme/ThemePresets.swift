import SwiftUI

extension Theme {
    /// 从提案里的八个语义色派生界面需要的其余槽位。
    static func make(
        isDark: Bool,
        _ source: (
            background: UInt32,
            panel: UInt32,
            card: UInt32,
            imageWell: UInt32,
            textPrimary: UInt32,
            textSecondary: UInt32,
            border: UInt32,
            accent: UInt32
        )
    ) -> Theme {
        let deep = mix(source.panel, isDark ? 0x000000 : source.background, isDark ? 0.22 : 0.30)
        let backgrounds = [source.background, source.panel, source.card]
        let primary = ensureContrast(source.textPrimary, against: backgrounds, target: 4.5)
        let secondary = ensureContrast(source.textSecondary, against: backgrounds, target: 4.5)
        let tertiary = mix(secondary, source.background, 0.18)
        let borderStrong = mix(source.border, source.textSecondary, 0.30)
        let accentColor = Color(hex: source.accent)
        let warningBase: UInt32 = isDark ? 0xE0B07A : 0xA66A2E
        let endingBase: UInt32 = isDark ? 0xC0A0D0 : 0x8A6A9E
        let choiceBase: UInt32 = isDark ? 0xE09A6A : 0xB4663F
        let conditionBase: UInt32 = isDark ? 0x8FBFA8 : 0x5F7F6A
        return Theme(
            isDark: isDark,
            background: Color(hex: source.background),
            deep: Color(hex: deep),
            surface: Color(hex: source.panel),
            surfaceRaised: Color(hex: source.card),
            imageWell: Color(hex: source.imageWell),
            textPrimary: Color(hex: primary),
            textSecondary: Color(hex: secondary),
            textTertiary: Color(hex: tertiary),
            border: Color(hex: source.border),
            borderStrong: Color(hex: borderStrong),
            accent: accentColor,
            accentSoft: accentColor.opacity(isDark ? 0.22 : 0.16),
            warning: Color(hex: mix(source.accent, warningBase, 0.45)),
            ending: Color(hex: mix(source.accent, endingBase, 0.45)),
            choice: Color(hex: mix(source.accent, choiceBase, 0.45)),
            condition: Color(hex: mix(source.accent, conditionBase, 0.45)),
            neutralLine: Color(hex: tertiary)
        )
    }

    private static func ensureContrast(
        _ foreground: UInt32,
        against backgrounds: [UInt32],
        target: Double
    ) -> UInt32 {
        let worst = backgrounds.min { a, b in
            contrast(foreground, a) < contrast(foreground, b)
        } ?? foreground
        guard contrast(foreground, worst) < target else { return foreground }
        let direction: UInt32 = relativeLuminance(worst) > 0.5 ? 0x000000 : 0xFFFFFF
        var low = 0.0
        var high = 1.0
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if contrast(mix(foreground, direction, middle), worst) >= target {
                high = middle
            } else {
                low = middle
            }
        }
        return mix(foreground, direction, high)
    }

    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let first = relativeLuminance(a)
        let second = relativeLuminance(b)
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32, _ shift: UInt32) -> Double {
            let raw = Double((value >> shift) & 0xFF) / 255
            return raw <= 0.04045 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(hex, 16) + 0.7152 * channel(hex, 8) + 0.0722 * channel(hex, 0)
    }

    private static func mix(_ from: UInt32, _ to: UInt32, _ amount: Double) -> UInt32 {
        let t = max(0, min(1, amount))
        func channel(_ value: UInt32, _ shift: UInt32) -> Double {
            Double((value >> shift) & 0xFF)
        }
        let red = channel(from, 16) * (1 - t) + channel(to, 16) * t
        let green = channel(from, 8) * (1 - t) + channel(to, 8) * t
        let blue = channel(from, 0) * (1 - t) + channel(to, 0) * t
        return (UInt32(red.rounded()) << 16) | (UInt32(green.rounded()) << 8) | UInt32(blue.rounded())
    }
}


// MARK: - 1. 暖纸 · Warm Paper
extension Theme {
    static let warmPaperLight = Theme.make(
        isDark: false,
        (
            background: 0xF8F4EE,
            panel: 0xEEE8E0,
            card: 0xFFFCF7,
            imageWell: 0xF4EFE8,
            textPrimary: 0x3E332D,
            textSecondary: 0x72645A,
            border: 0xD8CEC2,
            accent: 0xA96F4B
        )
    )

    static let warmPaperDark = Theme.make(
        isDark: true,
        (
            background: 0x201C19,
            panel: 0x29231F,
            card: 0x332C27,
            imageWell: 0x26211D,
            textPrimary: 0xE8DED4,
            textSecondary: 0xB5A79A,
            border: 0x51463D,
            accent: 0xD5A27D
        )
    )

}


// MARK: - 2. 柔灰 · Soft Gray
extension Theme {
    static let softGrayLight = Theme.make(
        isDark: false,
        (
            background: 0xF3F4F5,
            panel: 0xE9EBED,
            card: 0xFAFBFC,
            imageWell: 0xEFF1F3,
            textPrimary: 0x34383D,
            textSecondary: 0x697078,
            border: 0xD0D4D8,
            accent: 0x527F9E
        )
    )

    static let softGrayDark = Theme.make(
        isDark: true,
        (
            background: 0x202225,
            panel: 0x292C30,
            card: 0x32363B,
            imageWell: 0x24272A,
            textPrimary: 0xE1E4E7,
            textSecondary: 0xAEB4BB,
            border: 0x484D53,
            accent: 0x8BB5D1
        )
    )

}


// MARK: - 3. 北境 · Nord
extension Theme {
    static let nordLight = Theme.make(
        isDark: false,
        (
            background: 0xECEFF3,
            panel: 0xE2E7ED,
            card: 0xF8FAFC,
            imageWell: 0xE8EDF2,
            textPrimary: 0x303946,
            textSecondary: 0x5F6B79,
            border: 0xCBD3DC,
            accent: 0x587FA8
        )
    )

    static let nordDark = Theme.make(
        isDark: true,
        (
            background: 0x252B34,
            panel: 0x2D3540,
            card: 0x37414E,
            imageWell: 0x29313B,
            textPrimary: 0xE0E6ED,
            textSecondary: 0xB2BDCA,
            border: 0x4B5868,
            accent: 0x91B6D8
        )
    )

}


// MARK: - 4. 旧时光 · Gruvbox
extension Theme {
    static let gruvboxLight = Theme.make(
        isDark: false,
        (
            background: 0xF3EBDD,
            panel: 0xE9DDC8,
            card: 0xFBF5E9,
            imageWell: 0xEFE4D1,
            textPrimary: 0x403B35,
            textSecondary: 0x766C5E,
            border: 0xD2C2A7,
            accent: 0x657F68
        )
    )

    static let gruvboxDark = Theme.make(
        isDark: true,
        (
            background: 0x282522,
            panel: 0x332E29,
            card: 0x3C3630,
            imageWell: 0x2E2A25,
            textPrimary: 0xE8DDC8,
            textSecondary: 0xB9AA91,
            border: 0x51483D,
            accent: 0x9DB58C
        )
    )

}


// MARK: - 5. 柔墨 · Soft Ink
extension Theme {
    static let softInkLight = Theme.make(
        isDark: false,
        (
            background: 0xF5F6F5,
            panel: 0xEBEEEC,
            card: 0xFCFDFC,
            imageWell: 0xF0F3F1,
            textPrimary: 0x343A39,
            textSecondary: 0x68716E,
            border: 0xD2D9D5,
            accent: 0x637E7A
        )
    )

    static let softInkDark = Theme.make(
        isDark: true,
        (
            background: 0x1C1F20,
            panel: 0x25292A,
            card: 0x2D3233,
            imageWell: 0x212526,
            textPrimary: 0xE0E5E3,
            textSecondary: 0xAAB3AF,
            border: 0x424A47,
            accent: 0x9ABBB5
        )
    )

}


// MARK: - 6. 猫奶油 · Catppuccin
extension Theme {
    static let catppuccinLight = Theme.make(
        isDark: false,
        (
            background: 0xEFF1F5,
            panel: 0xE6E9EF,
            card: 0xF9FAFD,
            imageWell: 0xF4F5F8,
            textPrimary: 0x4C4F69,
            textSecondary: 0x6C6F85,
            border: 0xCCD0DA,
            accent: 0x1E66F5
        )
    )

    static let catppuccinDark = Theme.make(
        isDark: true,
        (
            background: 0x1E1E2E,
            panel: 0x262637,
            card: 0x313244,
            imageWell: 0x252536,
            textPrimary: 0xCDD6F4,
            textSecondary: 0xA6ADC8,
            border: 0x45475A,
            accent: 0x89B4FA
        )
    )

}


// MARK: - 7. 日蚀 · Solarized
extension Theme {
    static let solarizedLight = Theme.make(
        isDark: false,
        (
            background: 0xF7F2E3,
            panel: 0xEEE8D5,
            card: 0xFFFBF0,
            imageWell: 0xF1EBD9,
            textPrimary: 0x475E66,
            textSecondary: 0x637A80,
            border: 0xD5CEBB,
            accent: 0x287EAE
        )
    )

    static let solarizedDark = Theme.make(
        isDark: true,
        (
            background: 0x07323C,
            panel: 0x0B3D49,
            card: 0x104754,
            imageWell: 0x092F39,
            textPrimary: 0xBDCCCD,
            textSecondary: 0x9BAFB1,
            border: 0x28525B,
            accent: 0x62ADD2
        )
    )

}


// MARK: - 8. 苔庭 · Moss Garden
extension Theme {
    static let mossGardenLight = Theme.make(
        isDark: false,
        (
            background: 0xF2F4EC,
            panel: 0xE6EADD,
            card: 0xFAFBF5,
            imageWell: 0xEDF0E5,
            textPrimary: 0x394238,
            textSecondary: 0x687262,
            border: 0xCDD5C4,
            accent: 0x617B54
        )
    )

    static let mossGardenDark = Theme.make(
        isDark: true,
        (
            background: 0x20251F,
            panel: 0x293027,
            card: 0x343C31,
            imageWell: 0x242A23,
            textPrimary: 0xE0E7D9,
            textSecondary: 0xB0BBA8,
            border: 0x4A5546,
            accent: 0x9EB98B
        )
    )

}


// MARK: - 9. 雨青 · Rain Slate
extension Theme {
    static let rainSlateLight = Theme.make(
        isDark: false,
        (
            background: 0xEEF3F3,
            panel: 0xE2EAEA,
            card: 0xFAFCFB,
            imageWell: 0xE9F0EF,
            textPrimary: 0x354344,
            textSecondary: 0x627273,
            border: 0xCBD8D7,
            accent: 0x4D8584
        )
    )

    static let rainSlateDark = Theme.make(
        isDark: true,
        (
            background: 0x202829,
            panel: 0x293334,
            card: 0x333F40,
            imageWell: 0x242D2E,
            textPrimary: 0xDFE8E7,
            textSecondary: 0xAFBFBE,
            border: 0x485958,
            accent: 0x8FC2BE
        )
    )

}


// MARK: - 10. 藕烟 · Lotus Haze
extension Theme {
    static let lotusHazeLight = Theme.make(
        isDark: false,
        (
            background: 0xF5F1F4,
            panel: 0xEBE5EC,
            card: 0xFCF9FC,
            imageWell: 0xF0EAF1,
            textPrimary: 0x403744,
            textSecondary: 0x706575,
            border: 0xD8CEDB,
            accent: 0x856B91
        )
    )

    static let lotusHazeDark = Theme.make(
        isDark: true,
        (
            background: 0x262129,
            panel: 0x302A35,
            card: 0x3A3340,
            imageWell: 0x2A2430,
            textPrimary: 0xE7DFEB,
            textSecondary: 0xB9ACBF,
            border: 0x51465A,
            accent: 0xBDA2C9
        )
    )

}


// MARK: - 11. 杏笺 · Apricot Letter
extension Theme {
    static let apricotLetterLight = Theme.make(
        isDark: false,
        (
            background: 0xF7F2EC,
            panel: 0xEEE7DF,
            card: 0xFFFBF6,
            imageWell: 0xF2EBE3,
            textPrimary: 0x41352F,
            textSecondary: 0x75665C,
            border: 0xDCCFC3,
            accent: 0xB87954
        )
    )

    static let apricotLetterDark = Theme.make(
        isDark: true,
        (
            background: 0x27211E,
            panel: 0x332A25,
            card: 0x3E322C,
            imageWell: 0x2D2521,
            textPrimary: 0xE9DED5,
            textSecondary: 0xB8A89D,
            border: 0x55463D,
            accent: 0xD9A17B
        )
    )

}


// MARK: - 12. 海盐 · Sea Glass
extension Theme {
    static let seaGlassLight = Theme.make(
        isDark: false,
        (
            background: 0xF0F5F4,
            panel: 0xE4ECEB,
            card: 0xFAFCFB,
            imageWell: 0xEAF1F0,
            textPrimary: 0x344244,
            textSecondary: 0x637375,
            border: 0xCCD9D8,
            accent: 0x4D8987
        )
    )

    static let seaGlassDark = Theme.make(
        isDark: true,
        (
            background: 0x1D292B,
            panel: 0x263436,
            card: 0x303F41,
            imageWell: 0x222F31,
            textPrimary: 0xDFE9E8,
            textSecondary: 0xAFC0C0,
            border: 0x46595A,
            accent: 0x8FC9C2
        )
    )

}


// MARK: - 13. 赤陶 · Terracotta
extension Theme {
    static let terracottaLight = Theme.make(
        isDark: false,
        (
            background: 0xF5F0EA,
            panel: 0xEAE2D9,
            card: 0xFCF9F4,
            imageWell: 0xF0E8DF,
            textPrimary: 0x413630,
            textSecondary: 0x75675E,
            border: 0xD9CCC0,
            accent: 0xA65F4D
        )
    )

    static let terracottaDark = Theme.make(
        isDark: true,
        (
            background: 0x28211E,
            panel: 0x342A26,
            card: 0x40332D,
            imageWell: 0x2D2521,
            textPrimary: 0xE8DED5,
            textSecondary: 0xB7A89D,
            border: 0x57463E,
            accent: 0xD28C75
        )
    )

}


// MARK: - 14. 雾杉 · Mist Pine
extension Theme {
    static let mistPineLight = Theme.make(
        isDark: false,
        (
            background: 0xEEF3EF,
            panel: 0xE2EAE4,
            card: 0xFAFCFA,
            imageWell: 0xE9F0EA,
            textPrimary: 0x34423A,
            textSecondary: 0x627267,
            border: 0xCBD8CE,
            accent: 0x587D68
        )
    )

    static let mistPineDark = Theme.make(
        isDark: true,
        (
            background: 0x1F2825,
            panel: 0x28332F,
            card: 0x333F39,
            imageWell: 0x232D29,
            textPrimary: 0xDEE8E0,
            textSecondary: 0xADBBB1,
            border: 0x46564B,
            accent: 0x91B9A0
        )
    )

}


// MARK: - 15. 石英 · Quartz
extension Theme {
    static let quartzLight = Theme.make(
        isDark: false,
        (
            background: 0xF4F1F2,
            panel: 0xEAE5E9,
            card: 0xFBF9FA,
            imageWell: 0xEFEAED,
            textPrimary: 0x403941,
            textSecondary: 0x706773,
            border: 0xD7CFD7,
            accent: 0x806C89
        )
    )

    static let quartzDark = Theme.make(
        isDark: true,
        (
            background: 0x252226,
            panel: 0x302B31,
            card: 0x3A343D,
            imageWell: 0x29252B,
            textPrimary: 0xE7E0E8,
            textSecondary: 0xB8ADB9,
            border: 0x504650,
            accent: 0xB49BC0
        )
    )

}


// MARK: - 16. 靛笺 · Indigo Paper
extension Theme {
    static let indigoPaperLight = Theme.make(
        isDark: false,
        (
            background: 0xF0F3F8,
            panel: 0xE4EAF2,
            card: 0xFAFCFF,
            imageWell: 0xEBF0F6,
            textPrimary: 0x343D4D,
            textSecondary: 0x657185,
            border: 0xCED7E4,
            accent: 0x5E73A6
        )
    )

    static let indigoPaperDark = Theme.make(
        isDark: true,
        (
            background: 0x202532,
            panel: 0x293141,
            card: 0x343E50,
            imageWell: 0x242C3A,
            textPrimary: 0xE0E6F0,
            textSecondary: 0xAFBACB,
            border: 0x4A576D,
            accent: 0x9EAFDA
        )
    )

}


// MARK: - 17. 蜂蜜 · Hushed Honey
extension Theme {
    static let hushedHoneyLight = Theme.make(
        isDark: false,
        (
            background: 0xF5F2E9,
            panel: 0xECE7D9,
            card: 0xFCFAF2,
            imageWell: 0xF0EBDD,
            textPrimary: 0x403A30,
            textSecondary: 0x756D5E,
            border: 0xD9D0BC,
            accent: 0x9A7840
        )
    )

    static let hushedHoneyDark = Theme.make(
        isDark: true,
        (
            background: 0x26231D,
            panel: 0x312C23,
            card: 0x3B3529,
            imageWell: 0x2B271F,
            textPrimary: 0xE9E2D1,
            textSecondary: 0xB8AD96,
            border: 0x554B39,
            accent: 0xD1B16E
        )
    )

}


// MARK: - 18. 月白 · Moonlit
extension Theme {
    static let moonlitLight = Theme.make(
        isDark: false,
        (
            background: 0xF2F4F6,
            panel: 0xE7EBEF,
            card: 0xFBFCFD,
            imageWell: 0xEDF0F3,
            textPrimary: 0x353C46,
            textSecondary: 0x68727F,
            border: 0xD0D7DF,
            accent: 0x657F9C
        )
    )

    static let moonlitDark = Theme.make(
        isDark: true,
        (
            background: 0x20242B,
            panel: 0x292E37,
            card: 0x343B46,
            imageWell: 0x242932,
            textPrimary: 0xE1E6EC,
            textSecondary: 0xB0BAC6,
            border: 0x4A5361,
            accent: 0x9CB9D8
        )
    )

}


// MARK: - 19. 山岚 · Mountain Veil
extension Theme {
    static let mountainVeilLight = Theme.make(
        isDark: false,
        (
            background: 0xF1F2F0,
            panel: 0xE6E9E6,
            card: 0xFAFBF9,
            imageWell: 0xECEFED,
            textPrimary: 0x394044,
            textSecondary: 0x687276,
            border: 0xD0D7D6,
            accent: 0x5D7F8A
        )
    )

    static let mountainVeilDark = Theme.make(
        isDark: true,
        (
            background: 0x222629,
            panel: 0x2C3236,
            card: 0x373F44,
            imageWell: 0x262C30,
            textPrimary: 0xE1E6E5,
            textSecondary: 0xB0B9B9,
            border: 0x4B5559,
            accent: 0x94B8C2
        )
    )

}


// MARK: - 20. 竹影 · Bamboo Ink
extension Theme {
    static let bambooInkLight = Theme.make(
        isDark: false,
        (
            background: 0xF1F4ED,
            panel: 0xE5EBDD,
            card: 0xFAFCF6,
            imageWell: 0xEBF0E5,
            textPrimary: 0x354139,
            textSecondary: 0x657267,
            border: 0xCDD7CB,
            accent: 0x587C6A
        )
    )

    static let bambooInkDark = Theme.make(
        isDark: true,
        (
            background: 0x1E2724,
            panel: 0x27312D,
            card: 0x323D37,
            imageWell: 0x222D28,
            textPrimary: 0xDFE8DF,
            textSecondary: 0xAFBCAF,
            border: 0x46564C,
            accent: 0x91BBA5
        )
    )

}

extension Theme {
    /// 兼容既有引用：Catppuccin 的浅深两版。
    static let latte = catppuccinLight
    static let mocha = catppuccinDark
}
