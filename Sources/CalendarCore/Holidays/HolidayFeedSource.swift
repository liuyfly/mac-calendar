import Foundation

/// A day of the statutory arrangement, in this app's canonical shape.
///
/// This matches holiday-cn's schema, which every source is normalised into
/// before it is cached, so the cache format does not depend on which source
/// happened to answer.
public struct HolidayDay: Codable, Equatable {
    public let date: String        // yyyy-MM-dd
    public let isOffDay: Bool
    public let name: String
}

/// A remote publisher of China's statutory holiday arrangement.
///
/// Several are tried in order. The State Council's schedule is the same
/// document whichever project republishes it, so a fallback is about
/// availability — a repository going away, an npm release lagging, a CDN being
/// unreachable — not about preferring one project's numbers over another's.
public struct HolidayFeedSource {
    public let name: String
    /// `{year}` is substituted.
    public let urlTemplate: String
    /// Returns nil when the payload does not parse or carries no days.
    public let parse: (Data, Int) -> [HolidayDay]?

    public func url(for year: Int) -> URL? {
        URL(string: urlTemplate.replacingOccurrences(of: "{year}", with: String(year)))
    }

    /// Ordered by preference.
    ///
    /// holiday-cn leads because it is a pure data repository updated by CI
    /// straight from the State Council announcements, it publishes a year
    /// ahead of chinese-days (2027 is already there), and its raw files are
    /// served directly from the repository, so a commit is live immediately
    /// rather than waiting on an npm release. It is listed twice, on two CDNs,
    /// because jsDelivr has been unreachable from mainland China before.
    public static let defaults: [HolidayFeedSource] = [
        holidayCN(name: "holiday-cn (jsDelivr)",
                  template: "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/{year}.json"),
        holidayCN(name: "holiday-cn (raw.githubusercontent)",
                  template: "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/{year}.json"),
        chineseDays,
    ]

    // MARK: - Sources

    /// `{ "year": 2026, "papers": [...], "days": [{ date, isOffDay, name }] }`
    static func holidayCN(name: String, template: String) -> HolidayFeedSource {
        HolidayFeedSource(name: name, urlTemplate: template) { data, year in
            struct Feed: Decodable {
                let year: Int
                let days: [HolidayDay]
            }
            guard let feed = try? JSONDecoder().decode(Feed.self, from: data),
                  feed.year == year,
                  !feed.days.isEmpty else { return nil }
            return feed.days
        }
    }

    /// `{ "holidays": { "2026-01-01": "New Year's Day,元旦,1" }, "workdays": {…} }`
    ///
    /// The payload carries no year of its own, so the requested year is used to
    /// reject a file that answered with the wrong dates.
    static let chineseDays = HolidayFeedSource(
        name: "chinese-days",
        urlTemplate: "https://cdn.jsdelivr.net/npm/chinese-days/dist/years/{year}.json"
    ) { data, year in
        struct Feed: Decodable {
            let holidays: [String: String]
            let workdays: [String: String]
        }
        guard let feed = try? JSONDecoder().decode(Feed.self, from: data) else { return nil }

        let prefix = String(year)
        var days: [HolidayDay] = []
        for (date, label) in feed.holidays where date.hasPrefix(prefix) {
            days.append(HolidayDay(date: date, isOffDay: true, name: chineseName(from: label)))
        }
        for (date, label) in feed.workdays where date.hasPrefix(prefix) {
            days.append(HolidayDay(date: date, isOffDay: false, name: chineseName(from: label)))
        }
        // `inLieuDays` is deliberately ignored: those dates already appear in
        // `holidays`, and the distinction is not something the grid shows.
        guard !days.isEmpty else { return nil }
        return days.sorted { $0.date < $1.date }
    }

    /// Pulls 元旦 out of "New Year's Day,元旦,1".
    private static func chineseName(from label: String) -> String {
        let parts = label.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return label }
        return String(parts[1])
    }
}
