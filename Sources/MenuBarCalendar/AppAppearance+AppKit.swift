import AppKit
import CalendarCore

extension AppAppearance {
    /// `nil` hands the decision back to the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Applies the theme to every window this app owns.
    ///
    /// The status item is deliberately not covered: its image is a template
    /// image tinted by the menu bar, which follows the system's appearance and
    /// the user's wallpaper. Forcing it dark while the menu bar is light would
    /// make the glyph invisible.
    func apply() {
        NSApp.appearance = nsAppearance
    }
}
