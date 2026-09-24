import Foundation
import Combine

/// User settings, backed by `UserDefaults`.
public final class Preferences: ObservableObject {
    public static let shared = Preferences()

    private enum Key {
        static let appearance = "appearance"
        static let statusBarStyle = "statusBarStyle"
        static let statusBarFormat = "statusBarFormat"
        static let weekStartsOnMonday = "weekStartsOnMonday"
        static let showSolarTerms = "showSolarTerms"
        static let showHolidayBadges = "showHolidayBadges"
        static let holidayDataUpdatedAt = "holidayDataUpdatedAt"
    }

    /// Placeholders accepted in `statusBarFormat`.
    public static let formatTokens: [(token: String, description: String)] = [
        ("{M}", "月份"),
        ("{d}", "日"),
        ("{周}", "星期"),
        ("{农历}", "农历日期"),
        ("{月}", "农历月"),
        ("{节气}", "当日节气"),
        ("{生肖}", "生肖"),
    ]

    public static let defaultFormat = "{M}月{d}日 {周}"

    /// What the status item shows.
    public enum StatusBarStyle: String, CaseIterable {
        case icon
        case text
        case both

        public var label: String {
            switch self {
            case .icon: return "图标"
            case .text: return "文字"
            case .both: return "图标 + 文字"
            }
        }

        public var showsIcon: Bool { self != .text }
        public var showsText: Bool { self != .icon }
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.appearance: AppAppearance.system.rawValue,
            Key.statusBarStyle: StatusBarStyle.icon.rawValue,
            Key.statusBarFormat: Self.defaultFormat,
            Key.weekStartsOnMonday: true,
            Key.showSolarTerms: true,
            Key.showHolidayBadges: true,
        ])
    }

    @Published public var revision = 0

    private func bump() { revision &+= 1 }

    public var appearance: AppAppearance {
        get {
            guard let raw = defaults.string(forKey: Key.appearance),
                  let value = AppAppearance(rawValue: raw) else { return .system }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance); bump() }
    }

    public var statusBarStyle: StatusBarStyle {
        get {
            guard let raw = defaults.string(forKey: Key.statusBarStyle),
                  let style = StatusBarStyle(rawValue: raw) else { return .icon }
            return style
        }
        set { defaults.set(newValue.rawValue, forKey: Key.statusBarStyle); bump() }
    }

    public var statusBarFormat: String {
        get { defaults.string(forKey: Key.statusBarFormat) ?? Self.defaultFormat }
        set { defaults.set(newValue, forKey: Key.statusBarFormat); bump() }
    }

    public var weekStartsOnMonday: Bool {
        get { defaults.bool(forKey: Key.weekStartsOnMonday) }
        set { defaults.set(newValue, forKey: Key.weekStartsOnMonday); bump() }
    }

    public var showSolarTerms: Bool {
        get { defaults.bool(forKey: Key.showSolarTerms) }
        set { defaults.set(newValue, forKey: Key.showSolarTerms); bump() }
    }

    public var showHolidayBadges: Bool {
        get { defaults.bool(forKey: Key.showHolidayBadges) }
        set { defaults.set(newValue, forKey: Key.showHolidayBadges); bump() }
    }

    public var holidayDataUpdatedAt: Date? {
        get { defaults.object(forKey: Key.holidayDataUpdatedAt) as? Date }
        set { defaults.set(newValue, forKey: Key.holidayDataUpdatedAt); bump() }
    }
}
