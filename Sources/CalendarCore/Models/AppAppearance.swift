import Foundation

/// How this app's own windows are themed, independently of the system setting.
///
/// Only the choice lives here. Applying it is platform specific: see
/// `AppAppearance+AppKit.swift` in the macOS app.
public enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}
