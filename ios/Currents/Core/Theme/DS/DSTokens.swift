import SwiftUI
import UIKit

/// Design tokens for the Luma-style redesign, translated from
/// docs/design/mockups/theme.css. Colours resolve per light/dark through
/// dynamic UIColors; the accent follows the angler's chosen colour theme.
enum DS {
    /// Side margin for every screen.
    static let gutter: CGFloat = 20

    enum Radius {
        static let thumb: CGFloat = 12
        static let card: CGFloat = 20
        static let button: CGFloat = 14
        static let sheet: CGFloat = 32
    }

    /// The 4-point spacing scale (--s1 … --s8).
    enum Space {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 20
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
    }

    enum Motion {
        static let fast: Double = 0.18
        static let med: Double = 0.32
        static let slow: Double = 0.56
        /// --spring: lively, about 16 percent overshoot. Cards, toasts, celebrations.
        static let spring = Animation.spring(duration: slow, bounce: 0.35)
        /// --spring-soft: settles with barely any overshoot. Pages, sheets, layout.
        static let softSpring = Animation.spring(duration: slow, bounce: 0.12)
        /// --ease-out at the medium duration.
        static let easeOut = Animation.timingCurve(0.22, 1, 0.36, 1, duration: med)
        /// Press feedback (dim in, dim out).
        static let press = Animation.easeOut(duration: fast)
    }

    /// The angler's theme colour (Settings > Appearance). The app root also
    /// applies it as `.tint`, so `.foregroundStyle(.tint)` tracks it live.
    static var accent: Color { ThemeOption.current.primary }

    /// Bite score ramp on the grade breakpoints (`ForecastFormat.grade`), so
    /// each grade word has one colour: slow < 25 ≤ low < 50 ≤ fair < 65 ≤
    /// good < 80 ≤ excellent (the accent).
    static func scoreColor(_ score: Int) -> Color {
        switch score {
        case ..<25: return .dsScoreSlow
        case 25..<50: return .dsScoreLow
        case 50..<65: return .dsScoreFair
        case 65..<80: return .dsScoreGood
        default: return accent
        }
    }

    /// Score colour for text: in light mode it is mixed 38 percent toward the
    /// text colour so yellow and green stay readable on white.
    static func scoreInk(_ score: Int) -> Color {
        ink(scoreColor(score))
    }

    /// A colour used as text or a small glyph: unchanged in dark mode, mixed 38%
    /// toward the text colour in light mode so yellows and light blues stay
    /// readable on white.
    static func ink(_ color: Color) -> Color {
        let base = UIColor(color)
        return Color(uiColor: UIColor { traits in
            guard traits.userInterfaceStyle != .dark else { return base }
            return base.resolvedColor(with: traits)
                .ds_mixed(with: UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x13 / 255, alpha: 1),
                          amount: 0.38)
        })
    }

    /// Opacity of an art tint behind a thumbnail (--thumb-tint).
    static func thumbTintOpacity(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.30 : 0.20 }
    /// Opacity of a score tint behind a hero (--hero-tint).
    static func heroTintOpacity(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.10 : 0.07 }
}

// MARK: - Colour tokens

/// Usable as `Color.dsText` and, inside any ShapeStyle slot, as `.dsText`.
extension ShapeStyle where Self == Color {
    static var dsBackground: Color { DSPalette.background }
    static var dsElevated: Color { DSPalette.elevated }
    static var dsFill: Color { DSPalette.fill }
    static var dsFill2: Color { DSPalette.fill2 }
    static var dsSeparator: Color { DSPalette.separator }
    static var dsText: Color { DSPalette.text }
    static var dsText2: Color { DSPalette.text2 }
    static var dsText3: Color { DSPalette.text3 }
    /// Filled primary button: near black in light, near white in dark.
    static var dsPrimaryButton: Color { DSPalette.primaryButton }
    static var dsOnPrimary: Color { DSPalette.onPrimary }
    /// Secondary (tonal) button fill: the text colour at 8 percent.
    static var dsTonal: Color { DSPalette.tonal }
    static var dsScrim: Color { DSPalette.scrim }
    static var dsAccent: Color { DS.accent }
    static var dsScoreSlow: Color { DSPalette.scoreSlow }
    static var dsScoreLow: Color { DSPalette.scoreLow }
    static var dsScoreFair: Color { DSPalette.scoreFair }
    static var dsScoreGood: Color { DSPalette.scoreGood }
}

private enum DSPalette {
    static let background = dynamic(light: (0xFFFFFF, 1), dark: (0x000000, 1))
    static let elevated = dynamic(light: (0xFFFFFF, 1), dark: (0x1C1C1E, 1))
    static let fill = dynamic(light: (0xF2F2F7, 1), dark: (0x1C1C1E, 1))
    static let fill2 = dynamic(light: (0xE9E9EE, 1), dark: (0x2C2C2E, 1))
    static let separator = dynamic(light: (0x3C3C43, 0.14), dark: (0x545458, 0.48))
    static let text = dynamic(light: (0x111113, 1), dark: (0xF5F5F7, 1))
    static let text2 = dynamic(light: (0x3C3C43, 0.62), dark: (0xEBEBF5, 0.62))
    static let text3 = dynamic(light: (0x3C3C43, 0.32), dark: (0xEBEBF5, 0.30))
    static let primaryButton = dynamic(light: (0x111113, 1), dark: (0xF5F5F7, 1))
    static let onPrimary = dynamic(light: (0xFFFFFF, 1), dark: (0x000000, 1))
    static let tonal = dynamic(light: (0x111113, 0.08), dark: (0xF5F5F7, 0.08))
    static let scrim = dynamic(light: (0x000000, 0.28), dark: (0x000000, 0.55))
    static let scoreSlow = rgb(0xFF453A)
    static let scoreLow = rgb(0xFF9F0A)
    static let scoreFair = rgb(0xFFD60A)
    static let scoreGood = rgb(0x30D158)

    private static func uiColor(_ hex: UInt32, _ alpha: CGFloat) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    private static func rgb(_ hex: UInt32) -> Color { Color(uiColor: uiColor(hex, 1)) }

    private static func dynamic(light: (UInt32, CGFloat), dark: (UInt32, CGFloat)) -> Color {
        let l = uiColor(light.0, light.1)
        let d = uiColor(dark.0, dark.1)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? d : l })
    }
}

extension UIColor {
    /// Linear mix toward `other` by `amount` (0 keeps self, 1 is other).
    fileprivate func ds_mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(1, max(0, amount))
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}

// MARK: - Screen helpers

extension View {
    /// Pure black (dark) or white (light) page background, edge to edge.
    func dsScreenBackground() -> some View {
        background(Color.dsBackground.ignoresSafeArea())
    }
}
