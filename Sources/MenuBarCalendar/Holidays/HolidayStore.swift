import Foundation

/// Statutory status of a single day.
enum HolidayStatus: Equatable {
    /// A mandated day off (放假).
    case off(name: String)
    /// A make-up working day that falls on a weekend (调休补班).
    case workday(name: String)
}

/// Shape of the bundled file: every year in one document.
private struct BundledHolidayFile: Decodable {
    struct Year: Decodable {
        let papers: [String]?
        let days: [HolidayDay]
    }
    let years: [String: Year]
}

/// Shape of a cached year, written by this app after normalising whichever
/// source answered.
private struct CachedYear: Codable {
    let year: Int
    let source: String?
    let days: [HolidayDay]
}

/// Looks up statutory holidays and make-up workdays.
///
/// The State Council publishes each year's arrangement around November of the
/// preceding year, so the bundled table always goes stale. Lookups fall back
/// through: downloaded cache → bundled file → no data (cells simply show no
/// badge, rather than guessing).
final class HolidayStore {
    static let shared = HolidayStore()

    /// `{year: {"yyyy-MM-dd": status}}`
    private var table: [Int: [String: HolidayStatus]] = [:]
    private var loadedYears: Set<Int> = []
    private let lock = NSLock()


    private init() {
        loadBundled()
        loadCached()
    }

    // MARK: - Lookup

    func status(for date: Date) -> HolidayStatus? {
        guard let (year, key) = Self.key(for: date) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return table[year]?[key]
    }

    /// Builds the `yyyy-MM-dd` key by hand. A shared `DateFormatter` is not
    /// safe to mutate per call, and this lookup runs on every visible cell.
    private static func key(for date: Date) -> (year: Int, key: String)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        return (y, String(format: "%04d-%02d-%02d", y, m, d))
    }

    /// Years the store currently has data for.
    var availableYears: [Int] {
        lock.lock(); defer { lock.unlock() }
        return table.keys.sorted()
    }

    // MARK: - Loading

    private func loadBundled() {
        guard let url = Self.bundledFileURL(),
              let data = try? Data(contentsOf: url) else { return }
        merge(feedData: data)
    }

    /// Finds `holidays.json` across the three ways this code runs: a SwiftPM
    /// build (resource bundle), the packaged `.app` (Contents/Resources), and
    /// the standalone test runner (explicit path).
    private static func bundledFileURL() -> URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "holidays", withExtension: "json") {
            return url
        }
        #endif
        if let path = ProcessInfo.processInfo.environment["MENUBAR_CALENDAR_HOLIDAYS"] {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.url(forResource: "holidays", withExtension: "json")
    }

    private func loadCached() {
        guard let dir = Self.cacheDirectory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let cached = try? JSONDecoder().decode(CachedYear.self, from: data)
            else { continue }
            merge(days: cached.days, year: cached.year)
        }
    }

    private func merge(feedData data: Data) {
        guard let feed = try? JSONDecoder().decode(BundledHolidayFile.self, from: data) else {
            return
        }
        for (yearKey, year) in feed.years {
            guard let y = Int(yearKey) else { continue }
            merge(days: year.days, year: y)
        }
    }

    private func merge(days: [HolidayDay], year: Int) {
        guard !days.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        table[year] = Self.statusMap(from: days)
        loadedYears.insert(year)
    }

    private static func statusMap(from days: [HolidayDay]) -> [String: HolidayStatus] {
        var map: [String: HolidayStatus] = [:]
        for day in days {
            map[day.date] = day.isOffDay ? .off(name: day.name) : .workday(name: day.name)
        }
        return map
    }

    // MARK: - Remote refresh

    private static var cacheDirectory: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("MenuBarCalendar/Holidays", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Fetches the current and next year in the background.
    ///
    /// Each year tries the sources in order and stops at the first that
    /// answers, so a source being unreachable costs a round trip rather than
    /// the update. Failures are silent by design: the calendar stays usable on
    /// the bundled data, and a year with no data shows no badge rather than a
    /// guessed one.
    /// - Parameter force: skips the throttle, for the button in preferences.
    func refreshFromRemote(sources: [HolidayFeedSource] = HolidayFeedSource.defaults,
                           force: Bool = false,
                           completion: (([Int]) -> Void)? = nil) {
        // The arrangement changes once a year. Checking on every launch mostly
        // spends requests on a year that is not published yet — each miss walks
        // all three sources — so a launch check is skipped if one succeeded
        // recently.
        if !force, let last = Preferences.shared.holidayDataUpdatedAt,
           Date().timeIntervalSince(last) < 12 * 3600 {
            completion?([])
            return
        }

        let currentYear = Calendar(identifier: .gregorian)
            .dateComponents([.year], from: Date()).year ?? 2026
        let group = DispatchGroup()
        var updated: [Int] = []
        let updateLock = NSLock()

        for year in [currentYear, currentYear + 1] {
            group.enter()
            fetch(year: year, from: sources[...]) { succeeded in
                if succeeded {
                    updateLock.lock(); updated.append(year); updateLock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if !updated.isEmpty {
                Preferences.shared.holidayDataUpdatedAt = Date()
            }
            completion?(updated.sorted())
        }
    }

    /// Tries `sources` in order until one yields usable data for `year`.
    private func fetch(year: Int,
                       from sources: ArraySlice<HolidayFeedSource>,
                       completion: @escaping (Bool) -> Void) {
        guard let source = sources.first, let url = source.url(for: year) else {
            completion(false)
            return
        }
        let remaining = sources.dropFirst()

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return completion(false) }

            guard let data,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let days = source.parse(data, year) else {
                // Anything unusable — 404 for a year not published yet, a CDN
                // error page, a schema change — moves on to the next source.
                self.fetch(year: year, from: remaining, completion: completion)
                return
            }

            self.merge(days: days, year: year)
            self.writeCache(days: days, year: year, source: source.name)
            completion(true)
        }.resume()
    }

    private func writeCache(days: [HolidayDay], year: Int, source: String) {
        guard let dir = Self.cacheDirectory else { return }
        let cached = CachedYear(year: year, source: source, days: days)
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: dir.appendingPathComponent("\(year).json"))
    }
}
