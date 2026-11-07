import SwiftUI
import UIKit

// MARK: - Color tokens

extension Color {
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red, green, blue: CGFloat
        if cleaned.count == 8 {
            red = CGFloat((value >> 24) & 0xFF) / 255
            green = CGFloat((value >> 16) & 0xFF) / 255
            blue = CGFloat((value >> 8) & 0xFF) / 255
            self.init(red: red, green: green, blue: blue, alpha: CGFloat(value & 0xFF) / 255)
        } else {
            red = CGFloat((value >> 16) & 0xFF) / 255
            green = CGFloat((value >> 8) & 0xFF) / 255
            blue = CGFloat(value & 0xFF) / 255
            self.init(red: red, green: green, blue: blue, alpha: 1)
        }
    }
}

enum AppColor {
    static let page = Color(light: "#FBF7EE", dark: "#1E1B17")
    static let surface = Color(light: "#FFFFFF", dark: "#2A2620")
    static let textPrimary = Color(light: "#4A4843", dark: "#F3EDE2")
    // Light-mode secondary/muted are darkened from the source tokens to meet 4.5:1 contrast.
    static let textSecondary = Color(light: "#75715F", dark: "#BDB6A7")
    static let textMuted = Color(light: "#7A7565", dark: "#948D80")
    static let accent = Color(light: "#B58F55", dark: "#D3A96D")
    /// Accessible accent for filled controls and accent-coloured text.
    static let accentStrong = Color(light: "#8A6A3A", dark: "#D3A96D")
    /// Accessible accent ink for small labels on the soft accent surface.
    static let accentInk = Color(light: "#7E5F32", dark: "#D3A96D")
    static let accentSoft = Color(light: "#F6EEE0", dark: "#332C23")
    static let divider = Color(light: "#EDE3D2", dark: "#3A342B")
    static let onAccent = Color(light: "#FFFFFF", dark: "#1E1B17")
    static let peach = Color(light: "#F6C9B3", dark: "#5C3F33")
    static let lavender = Color(light: "#DCCBF2", dark: "#4A3F5C")
    static let mint = Color(light: "#CDE9D6", dark: "#2F4A3C")
    static let blue = Color(light: "#A9D5F0", dark: "#2F4457")
    static let sand = Color(light: "#F1E2BC", dark: "#4A3F27")
    static let danger = Color(light: "#A5463B", dark: "#E58F82")
    static let success = Color(light: "#537A5C", dark: "#9AC4A3")
    static let shadow = Color(light: "#8A6A3A", dark: "#000000")

    static let initialPalette: [Color] = [peach, lavender, mint, blue, sand]

    static func initialColor(for id: UUID) -> Color {
        let byte = id.uuidString.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % initialPalette.count }
        return initialPalette[byte]
    }
}

// MARK: - Typography

enum AppFont {
    enum Weight {
        case regular, medium, semibold, bold

        var swiftUI: Font.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            }
        }

        var poppinsName: String {
            switch self {
            case .regular: "Poppins-Regular"
            case .medium: "Poppins-Medium"
            case .semibold: "Poppins-SemiBold"
            case .bold: "Poppins-Bold"
            }
        }
    }

    private static let poppinsRegular = UIFont(name: Weight.regular.poppinsName, size: 17) != nil
    private static let poppinsMedium = UIFont(name: Weight.medium.poppinsName, size: 17) != nil
    private static let poppinsSemibold = UIFont(name: Weight.semibold.poppinsName, size: 17) != nil
    private static let poppinsBold = UIFont(name: Weight.bold.poppinsName, size: 17) != nil

    static func hasPoppins(_ weight: Weight) -> Bool {
        switch weight {
        case .regular: poppinsRegular
        case .medium: poppinsMedium
        case .semibold: poppinsSemibold
        case .bold: poppinsBold
        }
    }

    static func font(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        if hasPoppins(weight) {
            return .custom(weight.poppinsName, size: size, relativeTo: style)
        }
        let uiStyle: UIFont.TextStyle
        switch style {
        case .largeTitle: uiStyle = .largeTitle
        case .title: uiStyle = .title1
        case .title2: uiStyle = .title2
        case .title3: uiStyle = .title3
        case .headline: uiStyle = .headline
        case .subheadline: uiStyle = .subheadline
        case .callout: uiStyle = .callout
        case .footnote: uiStyle = .footnote
        case .caption: uiStyle = .caption1
        case .caption2: uiStyle = .caption2
        default: uiStyle = .body
        }
        let scaled = UIFontMetrics(forTextStyle: uiStyle).scaledValue(for: size)
        return .system(size: scaled, weight: weight.swiftUI, design: .rounded)
    }

    // Frequently used reference roles.
    static func largeTitle() -> Font { font(34, .semibold, relativeTo: .largeTitle) }
    static func screenTitle() -> Font { font(32, .semibold, relativeTo: .largeTitle) }
    static func widgetTitle() -> Font { font(30, .semibold, relativeTo: .title) }
    static func frontWord() -> Font { font(46, .semibold, relativeTo: .largeTitle) }
    static func backTranslation() -> Font { font(36, .semibold, relativeTo: .largeTitle) }
    static func rowWord() -> Font { font(17, .bold, relativeTo: .body) }
    static func rowTranslation() -> Font { font(13, .regular, relativeTo: .footnote) }
    static func statCount() -> Font { font(22, .semibold, relativeTo: .title2) }
    static func fieldValue() -> Font { font(17, .semibold, relativeTo: .body) }
    static func primaryAction() -> Font { font(17, .bold, relativeTo: .body) }
    static func sectionLabel() -> Font { font(10.5, .semibold, relativeTo: .caption2) }
    static func body() -> Font { font(15, .regular, relativeTo: .body) }
    static func caption() -> Font { font(12, .regular, relativeTo: .caption) }
}

// MARK: - Geometry

enum AppMetrics {
    static let phoneInset: CGFloat = 20
    static let iPadInset: CGFloat = 24
    static let duoInset: CGFloat = 20
    static let duoLeftWidth: CGFloat = 220
    static let duoGap: CGFloat = 20
    static let iPadLeftWidth: CGFloat = 272
    static let iPadGap: CGFloat = 48
    static let maxWorkingWidth: CGFloat = 1180
    static let cardRadius: CGFloat = 20
    static let fieldRadius: CGFloat = 12
    static let actionHeight: CGFloat = 52
    static let primaryRadius: CGFloat = 16
    static let compactButton: CGFloat = 44

    enum LayoutMode {
        case compact
        case duo
        case pad

        static func resolve(width: CGFloat) -> LayoutMode {
            if width >= 760 { return .pad }
            if width >= 600 { return .duo }
            return .compact
        }

        var inset: CGFloat {
            switch self {
            case .compact: AppMetrics.phoneInset
            case .duo: AppMetrics.duoInset
            case .pad: AppMetrics.iPadInset
            }
        }

        var leftWidth: CGFloat {
            switch self {
            case .compact: 362
            case .duo: AppMetrics.duoLeftWidth
            case .pad: AppMetrics.iPadLeftWidth
            }
        }

        var gap: CGFloat {
            switch self {
            case .compact: 0
            case .duo: AppMetrics.duoGap
            case .pad: AppMetrics.iPadGap
            }
        }
    }
}

// MARK: - Shared modifiers

struct RaisedSurface: ViewModifier {
    var radius: CGFloat = AppMetrics.cardRadius
    var fill: Color = AppColor.surface
    var border: Bool = true

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .shadow(color: AppColor.shadow.opacity(0.08), radius: 12, x: 0, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border ? AppColor.divider : .clear, lineWidth: 1)
            )
    }
}

extension View {
    func raisedSurface(radius: CGFloat = AppMetrics.cardRadius, fill: Color = AppColor.surface, border: Bool = true) -> some View {
        modifier(RaisedSurface(radius: radius, fill: fill, border: border))
    }

    func sectionLabelStyle() -> some View {
        font(AppFont.sectionLabel())
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(AppColor.textSecondary)
    }
}

// MARK: - Initial tile

struct InitialTile: View {
    let word: String
    let id: UUID
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(AppColor.initialColor(for: id))
            .frame(width: size, height: size)
            .overlay(
                Text(String(word.first ?? "?").uppercased())
                    .font(AppFont.font(size * 0.4, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Rings

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    var size: CGFloat
    var label: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColor.divider, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(AppColor.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

// MARK: - Repeat progress

struct RepeatBars: View {
    var count: Int
    var threshold: Int
    var barWidth: CGFloat = 3
    var height: CGFloat = 13

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<max(threshold, 1), id: \.self) { index in
                Capsule()
                    .fill(index < count ? AppColor.accent : AppColor.divider)
                    .frame(width: barWidth, height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

struct SessionProgressDots: View {
    var total: Int
    var current: Int

    private var safeTotal: Int { max(1, total) }
    private var safeCurrent: Int { min(max(1, current), safeTotal) }

    var body: some View {
        Group {
            if safeTotal <= 12 {
                HStack(spacing: 6) {
                    ForEach(0..<safeTotal, id: \.self) { index in
                        let isCurrent = index == safeCurrent - 1
                        Circle()
                            .fill(
                                index < safeCurrent - 1
                                    ? AppColor.accent
                                    : (isCurrent ? AppColor.accentStrong : AppColor.divider)
                            )
                            .frame(width: isCurrent ? 8 : 6, height: isCurrent ? 8 : 6)
                            .overlay {
                                if isCurrent {
                                    Circle()
                                        .stroke(AppColor.accentStrong, lineWidth: 1.5)
                                        .frame(width: 13, height: 13)
                                }
                            }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView(value: Double(safeCurrent), total: Double(safeTotal))
                        .tint(AppColor.accent)
                        .frame(maxWidth: 180)
                    Text("\(safeCurrent) / \(safeTotal)")
                        .font(AppFont.font(11, .medium))
                        .foregroundStyle(AppColor.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session progress")
        .accessibilityValue("\(safeCurrent) of \(safeTotal)")
    }
}
