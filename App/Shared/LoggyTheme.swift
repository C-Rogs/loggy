import SwiftUI

// MARK: - Environment (set from RootView when user picks AppAppearance.dark)

private enum LoggyOLEDDarkPreferenceKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// True when the user explicitly selects **Dark** in Settings (OLED black canvas), not when System follows dark mode alone.
    var loggyOLEDDarkUserPreference: Bool {
        get { self[LoggyOLEDDarkPreferenceKey.self] }
        set { self[LoggyOLEDDarkPreferenceKey.self] = newValue }
    }
}

// MARK: - Colors

enum LoggyTheme {
    static func isOLEDDarkCanvas(oledPreference: Bool, colorScheme: ColorScheme) -> Bool {
        oledPreference && colorScheme == .dark
    }

    static func groupedCanvas(oledPreference: Bool, colorScheme: ColorScheme) -> Color {
        isOLEDDarkCanvas(oledPreference: oledPreference, colorScheme: colorScheme)
            ? .black
            : Color(.systemGroupedBackground)
    }

    /// Exercise cards, template rows, etc.
    static func elevatedGroupedCard(oledPreference: Bool, colorScheme: ColorScheme) -> Color {
        isOLEDDarkCanvas(oledPreference: oledPreference, colorScheme: colorScheme)
            ? Color(white: 0.11)
            : Color(.secondarySystemGroupedBackground)
    }

    /// Set row fill (must stay above black canvas for contrast).
    static func setRowSurface(oledPreference: Bool, colorScheme: ColorScheme) -> Color {
        isOLEDDarkCanvas(oledPreference: oledPreference, colorScheme: colorScheme)
            ? Color(white: 0.13)
            : Color(.systemBackground)
    }

    static func setRowStroke(oledPreference: Bool, colorScheme: ColorScheme) -> Color {
        isOLEDDarkCanvas(oledPreference: oledPreference, colorScheme: colorScheme)
            ? Color.white.opacity(0.12)
            : Color(.separator).opacity(0.4)
    }

    /// Summary / timer strips: solid dark bar on OLED instead of material blur on black.
    static func structuralBarFill(oledPreference: Bool, colorScheme: ColorScheme) -> Color {
        isOLEDDarkCanvas(oledPreference: oledPreference, colorScheme: colorScheme)
            ? Color(white: 0.08)
            : Color(.secondarySystemGroupedBackground)
    }

    static func navigationBarBackground(oledPreference: Bool, colorScheme: ColorScheme) -> Color {
        isOLEDDarkCanvas(oledPreference: oledPreference, colorScheme: colorScheme)
            ? .black
            : Color(.systemGroupedBackground)
    }
}
