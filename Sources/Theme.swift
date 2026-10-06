import SwiftUI

// MARK: - The world: a ruled index card
//
// THESIS  A recurring daily checklist as a library index card: ruled paper, a printed
//         margin rule, one punched position per task, and one dated stamp per finished
//         day. It refuses the category default of a frosted panel with an accent
//         progress ring, and it refuses the hero-metric streak counter.
// OWN-WORLD  Warm paper (#F7F2E9 light, #1C1A17 dark), one vermilion stamp colour
//         (#C6402A / #E4573A), hairline rules in paper-edge tone, monospace for every
//         date, count, and day stamp, and the system face for task titles so the card
//         stays native to the desktop it sits on.
// STORY   Today's card is on the desk. Every position not yet punched is readable at a
//         glance; one click leaves a mark; the last punch stamps the day.
// FIRST VIEWPORT  One 292pt card: a header carrying the title, the date in monospace
//         and the punched count; a vermilion title rule; punched task lines; a footer
//         with the length of the run and the last seven days as dated stamp cells. The
//         primary action is the task line itself.
// FORM   Index card / library date-due card, candidate 6 of my grounded list, seed
//        6d678932.
// FINISH  unreviewed and undocumented is unfinished; this build ends with the finish
//         review, the verdict, DESIGN.md, and every shipping raster carrying its
//         provenance.

func hex(_ value: String) -> Color {
    var raw = value
    if raw.hasPrefix("#") { raw.removeFirst() }
    var number: UInt64 = 0
    Scanner(string: raw).scanHexInt64(&number)
    return Color(.sRGB,
                 red: Double((number >> 16) & 0xFF) / 255,
                 green: Double((number >> 8) & 0xFF) / 255,
                 blue: Double(number & 0xFF) / 255,
                 opacity: 1)
}

/// The card's ink and stock, resolved once per appearance so the panel follows the
/// system light / dark setting instead of choosing one of its own.
struct CardTheme: Equatable {
    let isDark: Bool
    let paper: Color
    let rule: Color
    let marginRule: Color
    let ink: Color
    let inkSoft: Color
    let stamp: Color
    let hover: Color

    static let light = CardTheme(
        isDark: false,
        paper: hex("F7F2E9"),
        rule: hex("D3C5A8"),
        marginRule: hex("C4AC7E"),
        ink: hex("2A2622"),
        inkSoft: hex("6B6358"),   // 4.7:1 on the light stock
        stamp: hex("C6402A"),
        hover: hex("EFE7D8"))

    static let dark = CardTheme(
        isDark: true,
        paper: hex("1C1A17"),
        rule: hex("3E372D"),
        marginRule: hex("4B4132"),
        ink: hex("EFE9DF"),
        inkSoft: hex("A39A8D"),   // 6.2:1 on the dark stock
        stamp: hex("E4573A"),
        hover: hex("262320"))

    static func of(_ scheme: ColorScheme) -> CardTheme {
        scheme == .dark ? .dark : .light
    }
}

private struct CardThemeKey: EnvironmentKey {
    static let defaultValue = CardTheme.light
}

extension EnvironmentValues {
    var cardTheme: CardTheme {
        get { self[CardThemeKey.self] }
        set { self[CardThemeKey.self] = newValue }
    }
}

enum Face {
    static let cardTitle = Font.system(size: 15, weight: .semibold)
    static let task = Font.system(size: 13, weight: .regular)
    static let taskDone = Font.system(size: 13, weight: .regular)
    static let stampText = Font.system(size: 11, weight: .bold)

    static func meta(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Card stock. Elevation is declared once, by the window shadow, so the card carries no
/// border of its own.
struct PaperCard: View {
    @Environment(\.cardTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(theme.paper)
    }
}
