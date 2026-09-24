import Foundation

/// Renders the status bar title from the user's template.
public enum StatusBarFormatter {
    private static let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]

    public static func render(template: String, date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let lunar = LunarConverter.lunarDate(from: date)

        // Only evaluate solar terms if the template actually asks for one.
        let termName = template.contains("{节气}")
            ? (SolarTerms.term(on: date)?.name ?? "") : ""

        let weekday = (parts.weekday ?? 1) - 1
        let substitutions: [String: String] = [
            "{y}": String(parts.year ?? 0),
            "{M}": String(parts.month ?? 0),
            "{d}": String(parts.day ?? 0),
            "{周}": "周" + weekdayNames[max(0, min(6, weekday))],
            "{农历}": lunar.monthName + lunar.dayName,
            "{月}": lunar.monthName,
            "{日}": lunar.dayName,
            "{节气}": termName,
            "{生肖}": lunar.zodiac,
            "{干支}": lunar.stemBranch,
        ]

        var result = template
        for (token, value) in substitutions {
            result = result.replacingOccurrences(of: token, with: value)
        }
        // An empty {节气} can leave a double space behind.
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "日历" : trimmed
    }
}
