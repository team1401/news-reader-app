import SwiftUI

/// The "Quiet Desk" palette from the approved visual direction: warm tinted
/// neutrals, one quiet evergreen accent, and a muted sage-to-terracotta spectrum
/// for perspective. Colours are resolved per trait collection so both appearances
/// are first-class rather than one being an inversion of the other.
public enum BSColor {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    public static let bgBase = dynamic(light: 0xFBFBFA, dark: 0x1C1D1F)
    public static let bgRaised = dynamic(light: 0xFFFFFF, dark: 0x242629)
    public static let bgSunk = dynamic(light: 0xF3F3F1, dark: 0x121314)

    public static let textPrimary = dynamic(light: 0x2B2C2E, dark: 0xE3E4E6)
    public static let textSecondary = dynamic(light: 0x6C6E72, dark: 0x909296)
    public static let textTertiary = dynamic(light: 0x92959A, dark: 0x68696D)

    public static let border = dynamic(light: 0xE5E6E4, dark: 0x2D2E30)
    public static let borderStrong = dynamic(light: 0xCDCECB, dark: 0x3D3F43)

    public static let accent = dynamic(light: 0x2E5A44, dark: 0x7FB99C)
    public static let accentSoft = dynamic(light: 0xEEF5F1, dark: 0x1E2E26)

    /// For refresh failures and restricted-content notices. A muted clay rather
    /// than an alarm red: a stale source is information, not an emergency.
    public static let warning = dynamic(light: 0x9A5638, dark: 0xD09070)

    /// Foreground and background for an article-level estimate capsule.
    /// Colour supports scanning; the label is always readable without it.
    public static func lean(_ label: BiasLabel) -> (foreground: Color, background: Color) {
        switch label {
        case .left:
            return (dynamic(light: 0x3F6F52, dark: 0x8FBFA1), dynamic(light: 0xE2EFE7, dark: 0x1E2B21))
        case .center:
            return (dynamic(light: 0x725A24, dark: 0xD9BE6B), dynamic(light: 0xF4E9C5, dark: 0x272827))
        case .right:
            return (dynamic(light: 0x934A38, dark: 0xD69A85), dynamic(light: 0xF5E4DE, dark: 0x30221E))
        case .notApplicable:
            return (dynamic(light: 0x575E68, dark: 0xA8AEB8), dynamic(light: 0xEAECF0, dark: 0x232426))
        }
    }

    /// Colour for a *publisher* baseline, used only in the coverage strip.
    public static func baseline(_ bucket: BaselineBucket) -> Color {
        switch bucket {
        case .left: return dynamic(light: 0x3F6F52, dark: 0x6E9E82)
        case .centerLeft: return dynamic(light: 0x758364, dark: 0x94A183)
        case .center: return dynamic(light: 0x725A24, dark: 0xA98F4F)
        case .centerRight: return dynamic(light: 0xAB8862, dark: 0xB99A78)
        case .right: return dynamic(light: 0x934A38, dark: 0xB47060)
        case .unrated: return dynamic(light: 0x9BA0A8, dark: 0x5A5D63)
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Editorial serif for reporting, system sans for controls and metadata.
/// Every face is derived from a text style so Dynamic Type works throughout.
public enum BSFont {
    public static func serif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    public static func sans(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .default, weight: weight)
    }

    public static let masthead = Font.system(.caption, design: .default, weight: .bold)
    public static let editionDate = Font.system(.largeTitle, design: .serif, weight: .bold)
    public static let leadHeadline = Font.system(.title, design: .serif, weight: .bold)
    public static let riverHeadline = Font.system(.title3, design: .serif, weight: .bold)
    public static let clusterItemHeadline = Font.system(.headline, design: .serif, weight: .semibold)
    public static let dek = Font.system(.subheadline, design: .serif)
    public static let meta = Font.system(.caption, design: .default)
    public static let bandLabel = Font.system(.caption2, design: .default, weight: .bold)
}

public enum BSSpacing {
    public static let gutter: CGFloat = 20
    public static let s1: CGFloat = 4
    public static let s2: CGFloat = 8
    public static let s3: CGFloat = 12
    public static let s4: CGFloat = 16
    public static let s5: CGFloat = 20
    public static let s6: CGFloat = 24
    public static let s7: CGFloat = 32

    /// iPad and large iPhone widths get a measured column rather than a full-bleed
    /// line length; long serif lines are hard to read.
    public static let readingColumnMaxWidth: CGFloat = 700
}

/// A band label such as `LEAD STORY` — letterspaced small caps in the sans face.
public struct BandLabel: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text.uppercased())
            .font(BSFont.bandLabel)
            .tracking(1.2)
            .foregroundStyle(BSColor.textTertiary)
    }
}

/// Hairline divider matching the prototype's flat, shadow-free structure.
public struct BSDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(BSColor.border)
            .frame(height: 1)
    }
}

extension View {
    /// Constrains reading measure on iPad and large phones.
    func readingColumn() -> some View {
        frame(maxWidth: BSSpacing.readingColumnMaxWidth)
            .frame(maxWidth: .infinity)
    }
}
