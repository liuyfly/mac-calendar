import Foundation

/// A 6 x 7 grid of days for one month, padded with the tail of the previous
/// month and the head of the next so every month occupies the same height and
/// the popover never resizes as you page through.
public struct CalendarMonth {
    public let year: Int
    public let month: Int
    public let days: [DayInfo]
    /// Column headers, already rotated for the user's week start.
    public let weekdaySymbols: [String]
    /// Lunar months the displayed grid spans, e.g. "八月" or "七月—八月".
    public let lunarMonthSummary: String
    /// Sexagenary year and zodiac of the displayed month, e.g. "丙午 马年".
    public let yearSummary: String

    public static let rowCount = 6
    public static let columnCount = 7

    private static let mondayFirstSymbols = ["一", "二", "三", "四", "五", "六", "日"]
    private static let sundayFirstSymbols = ["日", "一", "二", "三", "四", "五", "六"]

    /// Builds the grid for `year`/`month`.
    public static func make(year: Int,
                     month: Int,
                     today: Date = Date(),
                     preferences: Preferences = .shared) -> CalendarMonth {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = preferences.weekStartsOnMonday ? 2 : 1

        let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))
            ?? Date()

        // Back up to the first cell of the week containing the 1st.
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -offset, to: firstOfMonth)
            ?? firstOfMonth

        let showTerms = preferences.showSolarTerms
        let showHolidays = preferences.showHolidayBadges

        var days: [DayInfo] = []
        days.reserveCapacity(rowCount * columnCount)
        for index in 0..<(rowCount * columnCount) {
            guard let date = calendar.date(byAdding: .day, value: index, to: gridStart) else { continue }
            days.append(DayInfoBuilder.build(
                date: date,
                displayedMonth: month,
                today: today,
                showSolarTerms: showTerms,
                showHolidays: showHolidays
            ))
        }

        let inMonth = days.filter(\.isInDisplayedMonth)
        let lunarNames = orderedUniqueLunarMonths(inMonth)

        return CalendarMonth(
            year: year,
            month: month,
            days: days,
            weekdaySymbols: preferences.weekStartsOnMonday ? mondayFirstSymbols : sundayFirstSymbols,
            lunarMonthSummary: lunarNames.joined(separator: "—"),
            yearSummary: inMonth.first.map { "\($0.lunar.stemBranch) \($0.lunar.zodiac)年" } ?? ""
        )
    }

    private static func orderedUniqueLunarMonths(_ days: [DayInfo]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for day in days {
            let name = day.lunar.monthName
            if seen.insert(name).inserted { result.append(name) }
        }
        return result
    }

    public static func current(today: Date = Date()) -> CalendarMonth {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month], from: today)
        return .make(year: parts.year ?? 2026, month: parts.month ?? 1, today: today)
    }
}
