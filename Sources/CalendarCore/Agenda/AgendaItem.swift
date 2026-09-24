import Foundation

/// A calendar event or a reminder, reduced to what the grid and the day list
/// show.
///
/// The core deliberately knows nothing about EventKit: the macOS app converts
/// its events and reminders into these, and the tests build them by hand.
public struct AgendaItem: Identifiable, Equatable {
    public enum Kind: Equatable {
        case event
        case reminder
    }

    /// An sRGB colour, so the core does not depend on a UI framework.
    public struct Color: Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// Unique per occurrence. A recurring event shares one identifier across
    /// its occurrences, so providers should fold the start date in.
    public let id: String
    public let kind: Kind
    public let title: String
    /// The event's start, or the reminder's due date.
    public let start: Date
    /// The event's end; `nil` for reminders.
    public let end: Date?
    /// An all-day event, or a reminder due on a date with no time.
    public let isAllDay: Bool
    /// The colour of the calendar or reminder list it belongs to.
    public let color: Color?

    public init(id: String, kind: Kind, title: String, start: Date, end: Date?,
                isAllDay: Bool, color: Color?) {
        self.id = id
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.color = color
    }
}

/// Supplies agenda items for a date range.
public protocol AgendaProvider: AnyObject {
    /// Delivers the items that overlap `[start, end)`: events that intersect
    /// the range, and incomplete reminders due inside it. Completed reminders
    /// and reminders without a due date are left out. `completion` may run on
    /// any queue.
    func fetchItems(from start: Date, to end: Date,
                    completion: @escaping ([AgendaItem]) -> Void)
}

/// Groups items by the local calendar days they cover and labels them.
public enum AgendaIndex {
    /// Items keyed by the local start of each day in `[start, end)` they
    /// touch, sorted for display.
    ///
    /// An event counts on every day it covers, so a three-day trip shows on
    /// all three. An event ending exactly at midnight does not spill into the
    /// next day.
    public static func byDay(_ items: [AgendaItem],
                             from start: Date,
                             to end: Date,
                             calendar: Calendar) -> [Date: [AgendaItem]] {
        var result: [Date: [AgendaItem]] = [:]
        for item in items {
            for day in days(covered: item, calendar: calendar)
            where day >= start && day < end {
                result[day, default: []].append(item)
            }
        }
        for (day, dayItems) in result {
            result[day] = sorted(dayItems, on: day, calendar: calendar)
        }
        return result
    }

    static func days(covered item: AgendaItem, calendar: Calendar) -> [Date] {
        let first = calendar.startOfDay(for: item.start)
        guard item.kind == .event, let end = item.end, end > item.start else {
            return [first]
        }
        // The end is exclusive: a 23:00–00:00 event belongs to one day only.
        let last = calendar.startOfDay(for: end.addingTimeInterval(-1))
        var days: [Date] = []
        var day = first
        // Bounded, so a malformed event spanning years cannot stall the grid.
        while day <= last && days.count < 400 {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// All-day entries first, then by time, then by title so the order is
    /// stable across refreshes.
    static func sorted(_ items: [AgendaItem], on day: Date, calendar: Calendar) -> [AgendaItem] {
        items.sorted { a, b in
            let aAllDay = coversWholeDay(a, on: day, calendar: calendar)
            let bAllDay = coversWholeDay(b, on: day, calendar: calendar)
            if aAllDay != bAllDay { return aAllDay }
            if a.start != b.start { return a.start < b.start }
            return a.title < b.title
        }
    }

    /// True for all-day items and for the middle days of a multi-day event.
    static func coversWholeDay(_ item: AgendaItem, on day: Date, calendar: Calendar) -> Bool {
        if item.isAllDay { return true }
        guard item.kind == .event, let end = item.end,
              let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
        return item.start <= day && end >= nextDay
    }

    /// "全天", "09:30–10:00", "22:00 起", "至 10:00" — the time column of the day
    /// list, as seen from `day`.
    public static func timeLabel(for item: AgendaItem, on day: Date, calendar: Calendar) -> String {
        if coversWholeDay(item, on: day, calendar: calendar) { return "全天" }
        guard item.kind == .event, let end = item.end else {
            return clock(item.start, calendar: calendar)
        }
        let startsToday = calendar.isDate(item.start, inSameDayAs: day)
        let endsToday = end <= (calendar.date(byAdding: .day, value: 1, to: day) ?? end)
        switch (startsToday, endsToday) {
        case (true, true):
            return end > item.start
                ? "\(clock(item.start, calendar: calendar))–\(clock(end, calendar: calendar))"
                : clock(item.start, calendar: calendar)
        case (true, false):
            return "\(clock(item.start, calendar: calendar)) 起"
        case (false, _):
            return "至 \(clock(end, calendar: calendar))"
        }
    }

    /// Built by hand: a shared `DateFormatter` is not safe to use this freely.
    private static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
