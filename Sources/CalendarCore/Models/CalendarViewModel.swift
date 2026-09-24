import Foundation
import Combine

/// Drives the popover: which month is on screen, which day is selected, and the
/// footer text.
public final class CalendarViewModel: ObservableObject {
    @Published public private(set) var month: CalendarMonth
    @Published public private(set) var selectedDate: Date?

    private var today: Date

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    public init(today: Date = Date()) {
        self.today = today
        self.month = .current(today: today)
    }

    // MARK: - Navigation

    public func step(_ delta: Int) {
        let base = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1))
        guard let base, let moved = calendar.date(byAdding: .month, value: delta, to: base) else {
            return
        }
        showMonth(containing: moved)
    }

    /// Displays the month `date` falls in, keeping the current `today`.
    private func showMonth(containing date: Date) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let m = parts.month else { return }
        month = .make(year: year, month: m, today: today)
    }

    public func goToToday() {
        today = Date()
        selectedDate = nil
        month = .current(today: today)
    }

    /// Rebuilds the grid, e.g. after preferences change or the date rolls over.
    public func reload() {
        let year = month.year, m = month.month
        today = Date()
        month = .make(year: year, month: m, today: today)
    }

    public func select(_ day: DayInfo) {
        // A day borrowed from the previous or next month is a navigation
        // affordance: clicking 8/31 or 10/1 from September's grid moves to that
        // month, with the clicked day selected so it stays visible.
        guard day.isInDisplayedMonth else {
            selectedDate = day.date
            showMonth(containing: day.date)
            return
        }

        if let selected = selectedDate, sameDay(selected, day.date) {
            selectedDate = nil    // tapping the selected day clears the selection
        } else {
            selectedDate = day.date
        }
    }

    public func isSelected(_ day: DayInfo) -> Bool {
        guard let selected = selectedDate else { return false }
        return sameDay(selected, day.date)
    }

    // MARK: - Footer

    /// The day the footer describes: the selection, else today, else the 1st of
    /// the displayed month when today is not on screen.
    private var focusedDay: DayInfo? {
        if let selected = selectedDate,
           let match = month.days.first(where: { sameDay($0.date, selected) }) {
            return match
        }
        if let todayCell = month.days.first(where: { $0.isToday && $0.isInDisplayedMonth }) {
            return todayCell
        }
        return month.days.first(where: \.isInDisplayedMonth)
    }

    public var footerTitle: String {
        guard let day = focusedDay else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: day.date)
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let weekday = names[max(0, min(6, (parts.weekday ?? 1) - 1))]
        return "\(parts.year ?? 0)年\(parts.month ?? 0)月\(parts.day ?? 0)日 星期\(weekday)"
    }

    public var footerDetail: String {
        guard let day = focusedDay else { return "" }
        var parts = [day.detailLine]

        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = .current
        parts.append("第 \(iso.component(.weekOfYear, from: day.date)) 周")

        if let countdown = Self.nextMajorEvent(after: day.date) {
            parts.append(countdown)
        }
        if case .workday = day.holidayStatus {
            parts.append("调休上班")
        }
        return parts.joined(separator: " · ")
    }

    /// "距中秋节还有 4 天" — the next major festival or statutory day off.
    ///
    /// Scans forward a bounded number of days so a year with no upcoming entry
    /// in the holiday table simply yields nothing instead of looping.
    private static func nextMajorEvent(after date: Date) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        for offset in 1...200 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { break }
            let lunar = LunarConverter.lunarDate(from: candidate)
            let festivals = Festivals.festivals(on: candidate, lunar: lunar)
            if let major = festivals.first(where: { $0.isMajor }) {
                return "距\(major.name)还有 \(offset) 天"
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func sameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }
}
