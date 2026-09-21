import Foundation

/// Everything one calendar cell needs to render itself.
struct DayInfo: Identifiable {
    let id: Date
    let date: Date
    let gregorianDay: Int
    let weekday: Int          // 1 = Sunday
    let lunar: LunarDate
    let solarTerm: SolarTerm?
    let festivals: [Festival]
    let holidayStatus: HolidayStatus?
    /// False for the leading/trailing days borrowed from adjacent months.
    let isInDisplayedMonth: Bool
    let isToday: Bool

    var isWeekend: Bool { weekday == 1 || weekday == 7 }

    /// What the secondary line shows, and how it should be coloured.
    enum Subtitle: Equatable {
        case festival(String)
        case solarTerm(String)
        case lunar(String)
    }

    /// Priority: festival > solar term > lunar date. 清明 is both a term and a
    /// statutory festival, and reads better in the festival colour.
    var subtitle: Subtitle {
        if let festival = festivals.first(where: { $0.isMajor }) {
            return .festival(festival.name)
        }
        if let term = solarTerm, term.name == "清明" {
            return .festival(term.name)
        }
        if let term = solarTerm {
            return .solarTerm(term.name)
        }
        if let festival = festivals.first {
            return .festival(festival.name)
        }
        return .lunar(lunar.cellLabel)
    }

    /// Line shown at the bottom of the popover for the selected day.
    var detailLine: String {
        var parts = [lunar.fullDescription]
        if let term = solarTerm { parts.append(term.name) }
        let names = festivals.map(\.name)
        if !names.isEmpty { parts.append(names.joined(separator: " · ")) }
        return parts.joined(separator: " · ")
    }
}

enum DayInfoBuilder {
    /// Assembles a `DayInfo`. Solar terms are skipped entirely when the user
    /// turns them off, which also skips the VSOP87 evaluation.
    static func build(date: Date,
                      displayedMonth: Int,
                      today: Date,
                      showSolarTerms: Bool,
                      showHolidays: Bool) -> DayInfo {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.month, .day, .weekday], from: date)
        let lunar = LunarConverter.lunarDate(from: date)

        return DayInfo(
            id: date,
            date: date,
            gregorianDay: parts.day ?? 1,
            weekday: parts.weekday ?? 1,
            lunar: lunar,
            solarTerm: showSolarTerms ? SolarTerms.term(on: date) : nil,
            festivals: Festivals.festivals(on: date, lunar: lunar),
            holidayStatus: showHolidays ? HolidayStore.shared.status(for: date) : nil,
            isInDisplayedMonth: parts.month == displayedMonth,
            isToday: calendar.isDate(date, inSameDayAs: today)
        )
    }
}
