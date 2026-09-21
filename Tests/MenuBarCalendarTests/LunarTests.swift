import AppKit
import Foundation

func runLunarTests() {
    TestRunner.suite("LunarDate — known conversions") {
        let cases: [(Date, String, String)] = [
            (day(2026, 9, 21), "丙午", "八月十一"),
            (day(2026, 2, 17), "丙午", "正月初一"),   // Spring Festival 2026
            (day(2025, 1, 29), "乙巳", "正月初一"),   // Spring Festival 2025
            (day(2026, 9, 25), "丙午", "八月十五"),   // Mid-Autumn 2026
            (day(2026, 12, 31), "丙午", "冬月廿三"),
        ]
        for (input, stemBranch, label) in cases {
            let lunar = LunarConverter.lunarDate(from: input)
            expectEqual(lunar.stemBranch, stemBranch, "\(input)")
            expectEqual(lunar.monthName + lunar.dayName, label, "\(input)")
        }
    }

    TestRunner.suite("LunarDate — zodiac turns at Spring Festival, not 1 Jan") {
        expectEqual(LunarConverter.lunarDate(from: day(2026, 1, 1)).zodiac, "蛇")
        expectEqual(LunarConverter.lunarDate(from: day(2026, 2, 16)).zodiac, "蛇")
        expectEqual(LunarConverter.lunarDate(from: day(2026, 2, 17)).zodiac, "马")
    }

    TestRunner.suite("LunarDate — leap month") {
        // 2028 has a leap fifth month.
        let lunar = LunarConverter.lunarDate(from: day(2028, 6, 25))
        expect(lunar.isLeapMonth, "2028-06-25 should be in a leap month")
        expectEqual(lunar.monthName, "闰五月")
    }

    TestRunner.suite("LunarDate — 除夕 tracks a short twelfth month") {
        // 2026's twelfth month has 29 days, so 除夕 is the 29th.
        let eve = LunarConverter.lunarDate(from: day(2026, 2, 16))
        expect(eve.isNewYearsEve, "2026-02-16 should be 除夕")
        expectEqual(eve.day, 29)
        expect(!LunarConverter.lunarDate(from: day(2026, 2, 15)).isNewYearsEve,
               "2026-02-15 should not be 除夕")
        // 2025's twelfth month has 30 days.
        let eve2025 = LunarConverter.lunarDate(from: day(2025, 1, 28))
        expect(eve2025.isNewYearsEve, "2025-01-28 should be 除夕")
    }

    TestRunner.suite("LunarDate — first of month shows the month name") {
        expectEqual(LunarConverter.lunarDate(from: day(2026, 9, 11)).cellLabel, "八月")
        expectEqual(LunarConverter.lunarDate(from: day(2026, 9, 21)).cellLabel, "十一")
    }
}

func runSolarTermTests() {
    func shanghaiParts(_ date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    TestRunner.suite("SolarTerms — published instants") {
        // Purple Mountain Observatory tables; tolerance one minute.
        let expected: [(year: Int, name: String, month: Int, dayOfMonth: Int, hour: Int, minute: Int)] = [
            (2024, "冬至", 12, 21, 17, 20),
            (2024, "立春", 2, 4, 16, 26),
            (2025, "立春", 2, 3, 22, 10),
            (2025, "冬至", 12, 21, 23, 2),
            (2026, "雨水", 2, 18, 23, 51),   // 8 minutes before midnight
            (2026, "秋分", 9, 23, 8, 5),
            (2026, "冬至", 12, 22, 4, 50),
        ]
        for item in expected {
            guard let term = SolarTerms.terms(inYear: item.year)
                .first(where: { $0.name == item.name }) else {
                expect(false, "missing \(item.year) \(item.name)")
                continue
            }
            let parts = shanghaiParts(term.date)
            expectEqual(parts.month ?? -1, item.month, "\(item.year) \(item.name) month")
            expectEqual(parts.day ?? -1, item.dayOfMonth, "\(item.year) \(item.name) day")
            let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            let target = item.hour * 60 + item.minute
            expect(abs(minutes - target) <= 1,
                   "\(item.year) \(item.name) off by \(minutes - target) min")
        }
    }

    TestRunner.suite("SolarTerms — ordering and spacing, 2020–2035") {
        for year in 2020...2035 {
            let terms = SolarTerms.terms(inYear: year)
            expectEqual(terms.count, 24, "\(year)")
            for (previous, next) in zip(terms, terms.dropFirst()) {
                let gap = next.date.timeIntervalSince(previous.date) / 86400
                expect(gap > 13.5 && gap < 16.5,
                       "\(year) \(previous.name)→\(next.name) gap \(String(format: "%.2f", gap))d")
            }
        }
    }

    TestRunner.suite("SolarTerms — every term stays inside its Gregorian year") {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        for year in 2020...2035 {
            for term in SolarTerms.terms(inYear: year) {
                expectEqual(calendar.component(.year, from: term.date), year,
                            "\(term.name) escaped \(year)")
            }
        }
    }

    TestRunner.suite("SolarTerms — cross-check against the low-accuracy formula") {
        // Guards against a mistyped VSOP87 coefficient: the two methods must
        // agree to well within the low-accuracy formula's own ~15 min error.
        for year in [2024, 2026, 2030] {
            for term in SolarTerms.terms(inYear: year) {
                let rough = roughSolarTermDate(year: year, longitude: term.longitude)
                let deltaMinutes = abs(term.date.timeIntervalSince(rough)) / 60
                expect(deltaMinutes < 20,
                       "\(year) \(term.name) differs from the rough formula by "
                       + "\(Int(deltaMinutes)) min")
            }
        }
    }
}

func runFestivalTests() {
    func names(_ date: Date) -> [String] {
        Festivals.festivals(on: date, lunar: LunarConverter.lunarDate(from: date)).map(\.name)
    }

    TestRunner.suite("Festivals — lunar") {
        expect(names(day(2026, 2, 17)).contains("春节"))
        expect(names(day(2026, 2, 16)).contains("除夕"))
        expect(names(day(2026, 9, 25)).contains("中秋节"))
        expect(names(day(2026, 6, 19)).contains("端午节"))
        expect(names(day(2026, 3, 3)).contains("元宵节"))
    }

    TestRunner.suite("Festivals — Gregorian and floating") {
        expect(names(day(2026, 10, 1)).contains("国庆节"))
        expect(names(day(2026, 9, 10)).contains("教师节"))
        expect(names(day(2026, 5, 10)).contains("母亲节"), "2nd Sunday of May 2026")
        expect(!names(day(2026, 5, 3)).contains("母亲节"), "1st Sunday is not 母亲节")
        expect(names(day(2026, 6, 21)).contains("父亲节"), "3rd Sunday of June 2026")
    }

    TestRunner.suite("Festivals — major outranks minor on the same day") {
        // 2026-09-25 is both 中秋节 and an ordinary lunar day.
        let list = Festivals.festivals(on: day(2026, 9, 25),
                                       lunar: LunarConverter.lunarDate(from: day(2026, 9, 25)))
        expect(list.first?.isMajor == true, "中秋节 should sort first")
    }
}

func runHolidayTests() {
    TestRunner.suite("HolidayStore — bundled 2026 arrangement") {
        let store = HolidayStore.shared
        expect(store.availableYears.contains(2026), "2026 data should be bundled")
        expect(store.availableYears.contains(2025), "2025 data should be bundled")

        if case .off(let name)? = store.status(for: day(2026, 10, 1)) {
            expectEqual(name, "国庆节")
        } else {
            expect(false, "2026-10-01 should be a day off")
        }

        if case .workday? = store.status(for: day(2026, 9, 20)) {
            // 2026-09-20 is a Sunday made into a working day for National Day.
        } else {
            expect(false, "2026-09-20 should be a make-up workday")
        }

        expect(store.status(for: day(2026, 9, 21)) == nil, "an ordinary Monday has no status")
        expect(store.status(for: day(2026, 2, 17)) != nil, "Spring Festival should be a day off")
    }
}

func runFormatterTests() {
    TestRunner.suite("StatusBarFormatter — templates") {
        let date = day(2026, 9, 21)
        expectEqual(StatusBarFormatter.render(template: "{M}月{d}日 {周}", date: date), "9月21日 周一")
        expectEqual(StatusBarFormatter.render(template: "{农历}", date: date), "八月十一")
        expectEqual(StatusBarFormatter.render(template: "{生肖}年", date: date), "马年")
        expectEqual(StatusBarFormatter.render(template: "{干支}", date: date), "丙午")
    }

    TestRunner.suite("StatusBarFormatter — empty solar term leaves no gap") {
        expectEqual(StatusBarFormatter.render(template: "{M}月{d}日 {节气}", date: day(2026, 9, 21)),
                    "9月21日")
        expectEqual(StatusBarFormatter.render(template: "{M}月{d}日 {节气}", date: day(2026, 9, 23)),
                    "9月23日 秋分")
    }

    TestRunner.suite("StatusBarFormatter — never renders empty") {
        expectEqual(StatusBarFormatter.render(template: "", date: day(2026, 9, 21)), "日历")
    }
}

func runCalendarMonthTests() {
    TestRunner.suite("CalendarMonth — grid shape") {
        for month in 1...12 {
            let grid = CalendarMonth.make(year: 2026, month: month)
            expectEqual(grid.days.count, 42, "2026-\(month)")
            expect(grid.days.contains { $0.gregorianDay == 1 && $0.isInDisplayedMonth },
                   "2026-\(month) must contain its own 1st")
        }
    }

    TestRunner.suite("CalendarMonth — February of a leap year") {
        let grid = CalendarMonth.make(year: 2028, month: 2)
        expectEqual(grid.days.filter(\.isInDisplayedMonth).count, 29)
    }

    TestRunner.suite("CalendarMonth — September 2026 renders as designed") {
        let grid = CalendarMonth.make(year: 2026, month: 9, today: day(2026, 9, 21))
        let byDay = Dictionary(uniqueKeysWithValues:
            grid.days.filter(\.isInDisplayedMonth).map { ($0.gregorianDay, $0) })

        expectEqual(byDay[7]?.subtitle, .solarTerm("白露"))
        expectEqual(byDay[11]?.subtitle, .lunar("八月"))
        expectEqual(byDay[21]?.subtitle, .lunar("十一"))
        expectEqual(byDay[23]?.subtitle, .solarTerm("秋分"))
        expectEqual(byDay[25]?.subtitle, .festival("中秋节"))
        expect(byDay[21]?.isToday == true, "21st should be today")

        if case .workday? = byDay[20]?.holidayStatus {
            // The Sunday traded away for the National Day break.
        } else {
            expect(false, "2026-09-20 should carry a 班 badge")
        }
    }
}

func runPreferenceTests() {
    TestRunner.suite("AppAppearance — maps to NSAppearance") {
        expect(AppAppearance.system.nsAppearance == nil, "system means: do not override")
        expect(AppAppearance.light.nsAppearance?.name == .aqua)
        expect(AppAppearance.dark.nsAppearance?.name == .darkAqua)
        expectEqual(AppAppearance.allCases.count, 3)
        // Raw values are persisted, so they must stay stable.
        expectEqual(AppAppearance.allCases.map(\.rawValue), ["system", "light", "dark"])
    }

    TestRunner.suite("StatusBarStyle — what each style shows") {
        expect(Preferences.StatusBarStyle.icon.showsIcon)
        expect(!Preferences.StatusBarStyle.icon.showsText)
        expect(!Preferences.StatusBarStyle.text.showsIcon)
        expect(Preferences.StatusBarStyle.text.showsText)
        expect(Preferences.StatusBarStyle.both.showsIcon)
        expect(Preferences.StatusBarStyle.both.showsText)
        expectEqual(Preferences.StatusBarStyle.allCases.map(\.rawValue),
                    ["icon", "text", "both"])
    }
}

func runViewModelTests() {
    /// Finds a day in the grid by its Gregorian day number and month membership.
    func cell(_ model: CalendarViewModel, day number: Int, inMonth: Bool) -> DayInfo? {
        model.month.days.first { $0.gregorianDay == number && $0.isInDisplayedMonth == inMonth }
    }

    TestRunner.suite("CalendarViewModel — clicking a trailing day moves to next month") {
        let model = CalendarViewModel(today: day(2026, 9, 21))
        expectEqual(model.month.month, 9)

        guard let oct1 = cell(model, day: 1, inMonth: false) else {
            return expect(false, "September's grid should show 10/1")
        }
        model.select(oct1)

        expectEqual(model.month.month, 10, "should have moved to October")
        expectEqual(model.month.year, 2026)
        guard let nowOct1 = cell(model, day: 1, inMonth: true) else {
            return expect(false, "October's grid should contain its own 1st")
        }
        expect(model.isSelected(nowOct1), "the clicked day stays selected")
    }

    TestRunner.suite("CalendarViewModel — clicking a leading day moves to previous month") {
        let model = CalendarViewModel(today: day(2026, 9, 21))
        guard let aug31 = cell(model, day: 31, inMonth: false) else {
            return expect(false, "September's grid should show 8/31")
        }
        model.select(aug31)

        expectEqual(model.month.month, 8, "should have moved to August")
        guard let nowAug31 = cell(model, day: 31, inMonth: true) else {
            return expect(false, "August's grid should contain its own 31st")
        }
        expect(model.isSelected(nowAug31), "the clicked day stays selected")
    }

    TestRunner.suite("CalendarViewModel — year rolls over at the December/January edge") {
        let model = CalendarViewModel(today: day(2026, 12, 15))
        expectEqual(model.month.year, 2026)
        guard let janDay = model.month.days.first(where: {
            !$0.isInDisplayedMonth && $0.gregorianDay <= 10
        }) else {
            return expect(false, "December's grid should show early January")
        }
        model.select(janDay)
        expectEqual(model.month.year, 2027)
        expectEqual(model.month.month, 1)
    }

    TestRunner.suite("CalendarViewModel — an in-month day only toggles selection") {
        let model = CalendarViewModel(today: day(2026, 9, 21))
        guard let sept15 = cell(model, day: 15, inMonth: true) else {
            return expect(false, "missing 9/15")
        }
        model.select(sept15)
        expectEqual(model.month.month, 9, "month must not change")
        expect(model.isSelected(sept15))
        model.select(sept15)
        expect(!model.isSelected(sept15), "clicking again clears the selection")
    }

    TestRunner.suite("CalendarViewModel — paging keeps the injected today") {
        let model = CalendarViewModel(today: day(2026, 9, 21))
        model.step(-1)
        expectEqual(model.month.month, 8)
        model.step(1)
        expectEqual(model.month.month, 9)
        expect(model.month.days.contains { $0.isToday && $0.gregorianDay == 21 },
               "21 September should still be marked as today")
    }
}

func runHolidayFeedTests() {
    let holidayCN = HolidayFeedSource.holidayCN(name: "test", template: "https://x/{year}.json")

    TestRunner.suite("HolidayFeedSource — holiday-cn schema") {
        let json = """
        {"year":2026,"papers":["https://gov.cn/x"],"days":[
          {"date":"2026-10-01","isOffDay":true,"name":"国庆节"},
          {"date":"2026-09-20","isOffDay":false,"name":"国庆节"}]}
        """.data(using: .utf8)!

        guard let days = holidayCN.parse(json, 2026) else {
            return expect(false, "valid payload should parse")
        }
        expectEqual(days.count, 2)
        expectEqual(days.first { $0.isOffDay }?.date, "2026-10-01")
        expectEqual(days.first { !$0.isOffDay }?.date, "2026-09-20")
        expectEqual(days.first?.name, "国庆节")

        // A CDN serving a stale or wrong file must not be accepted silently.
        expect(holidayCN.parse(json, 2027) == nil, "payload for another year is rejected")
        expect(holidayCN.parse(Data("not json".utf8), 2026) == nil)
        expect(holidayCN.parse(Data(#"{"year":2026,"days":[]}"#.utf8), 2026) == nil,
               "an empty day list is not an update")
    }

    TestRunner.suite("HolidayFeedSource — chinese-days schema") {
        let json = """
        {"holidays":{"2026-10-01":"National Day,国庆节,7","2026-10-02":"National Day,国庆节,7"},
         "workdays":{"2026-09-20":"National Day,国庆节,7"},
         "inLieuDays":{"2026-10-02":"National Day,国庆节,7"}}
        """.data(using: .utf8)!

        guard let days = HolidayFeedSource.chineseDays.parse(json, 2026) else {
            return expect(false, "valid payload should parse")
        }
        expectEqual(days.count, 3, "inLieuDays must not add duplicates")
        expectEqual(days.filter(\.isOffDay).count, 2)
        // The Chinese name is the second field of "English,中文,days".
        expectEqual(days.first?.name, "国庆节")
        // Sorted, so the cache file is stable between runs.
        expectEqual(days.map(\.date), ["2026-09-20", "2026-10-01", "2026-10-02"])

        // This schema carries no year, so dates are filtered by the requested one.
        expect(HolidayFeedSource.chineseDays.parse(json, 2027) == nil,
               "no dates for the requested year means no update")
    }

    TestRunner.suite("HolidayFeedSource — URL templating and fallback order") {
        expectEqual(holidayCN.url(for: 2027)?.absoluteString, "https://x/2027.json")

        let defaults = HolidayFeedSource.defaults
        expectEqual(defaults.count, 3)
        expect(defaults[0].urlTemplate.contains("holiday-cn"), "holiday-cn leads")
        expect(defaults[1].urlTemplate.contains("raw.githubusercontent"),
               "a second CDN for the same repository comes next")
        expect(defaults[2].urlTemplate.contains("chinese-days"),
               "chinese-days is the last resort")
        for source in defaults {
            expect(source.url(for: 2026)?.scheme == "https", "\(source.name) must use https")
        }
    }
}

func runLeapMonthConsistencyTests() {
    // The lunisolar calendar inserts a leap month wherever a lunar month holds
    // no 中气 — a solar term at a multiple of 30° of solar longitude. ICU's
    // chinese calendar and our VSOP87 series share no code, so this checks one
    // against the other across the whole supported range. A mistyped
    // coefficient or a time zone slip moves a term across a month boundary and
    // breaks the rule.
    TestRunner.suite("Solar terms agree with ICU's leap months, 1900–2100") {
        var offenders: [String] = []
        var checked = 0

        for year in 1900...2100 {
            for term in SolarTerms.terms(inYear: year) {
                guard term.longitude.truncatingRemainder(dividingBy: 30) == 0 else { continue }
                checked += 1
                let lunar = LunarConverter.lunarDate(from: term.date)
                if lunar.isLeapMonth {
                    offenders.append("\(year) \(term.name) in \(lunar.monthName)")
                }
            }
        }

        expectEqual(checked, 2412, "12 major terms a year over 201 years")
        expect(offenders.isEmpty,
               "no 中气 may fall in a leap month; got \(offenders.prefix(5).joined(separator: "; "))")
    }
}
