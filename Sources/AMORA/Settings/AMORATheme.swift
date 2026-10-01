import SwiftUI
import AppKit

/// A single, centralized set of colors for the whole app. Nothing else should
/// hard-code brand colors — views read `AppState.shared.settings.palette` so a
/// theme change recolors AMORA, the island, and the controls in one place.
struct ThemePalette {
    let accent: Color          // primary brand color (controls, highlights)
    let accentSoft: Color      // dimmer accent for glows / fills
    let eyeCore: Color         // robot eye fill
    let eyeGlow: Color         // robot eye bloom
    let shellTop: Color        // robot body gradient (top)
    let shellBottom: Color     // robot body gradient (bottom)
    let visor: Color           // robot face glass
    let surface: Color         // island / panel base
    let highlight: Color       // top edge sheen
}

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(red: r, green: g, blue: b)
}

extension Theme {
    var palette: ThemePalette {
        switch self {
        case .midnight:
            return ThemePalette(
                accent: rgb(0.32, 0.80, 1.0),
                accentSoft: rgb(0.25, 0.85, 1.0),
                eyeCore: rgb(0.93, 0.99, 1.0),
                eyeGlow: rgb(0.25, 0.85, 1.0),
                shellTop: rgb(0.18, 0.20, 0.26),
                shellBottom: rgb(0.10, 0.12, 0.16),
                visor: rgb(0.04, 0.06, 0.11),
                surface: rgb(0.05, 0.06, 0.09),
                highlight: .white
            )
        case .ocean:
            return ThemePalette(
                accent: rgb(0.18, 0.78, 0.80),
                accentSoft: rgb(0.20, 0.72, 0.78),
                eyeCore: rgb(0.90, 1.0, 0.99),
                eyeGlow: rgb(0.18, 0.82, 0.82),
                shellTop: rgb(0.12, 0.22, 0.26),
                shellBottom: rgb(0.07, 0.13, 0.17),
                visor: rgb(0.03, 0.08, 0.11),
                surface: rgb(0.04, 0.08, 0.10),
                highlight: .white
            )
        case .bubblegum:
            return ThemePalette(
                accent: rgb(1.0, 0.46, 0.72),
                accentSoft: rgb(1.0, 0.55, 0.78),
                eyeCore: rgb(1.0, 0.96, 0.99),
                eyeGlow: rgb(1.0, 0.50, 0.78),
                shellTop: rgb(0.26, 0.18, 0.24),
                shellBottom: rgb(0.16, 0.10, 0.15),
                visor: rgb(0.10, 0.05, 0.09),
                surface: rgb(0.09, 0.05, 0.08),
                highlight: .white
            )
        case .matrix:
            return ThemePalette(
                accent: rgb(0.30, 1.0, 0.52),
                accentSoft: rgb(0.35, 0.95, 0.55),
                eyeCore: rgb(0.90, 1.0, 0.92),
                eyeGlow: rgb(0.30, 1.0, 0.50),
                shellTop: rgb(0.12, 0.20, 0.14),
                shellBottom: rgb(0.06, 0.11, 0.08),
                visor: rgb(0.02, 0.07, 0.03),
                surface: rgb(0.03, 0.07, 0.04),
                highlight: .white
            )
        case .minimal:
            return ThemePalette(
                accent: rgb(0.86, 0.88, 0.92),
                accentSoft: rgb(0.78, 0.81, 0.86),
                eyeCore: rgb(0.98, 0.99, 1.0),
                eyeGlow: rgb(0.80, 0.84, 0.90),
                shellTop: rgb(0.22, 0.23, 0.26),
                shellBottom: rgb(0.13, 0.14, 0.16),
                visor: rgb(0.06, 0.07, 0.09),
                surface: rgb(0.07, 0.08, 0.10),
                highlight: .white
            )
        }
    }
}

/// Honors the system "Reduce Motion" setting plus the user's own animation
/// intensity slider. `scale` is the single multiplier views and the character
/// use for amplitude of non-essential motion (0 = calm/static, 1 = full).
enum MotionConfig {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
