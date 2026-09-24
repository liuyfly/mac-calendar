import Foundation

/// A date in the Chinese lunisolar calendar, resolved through the system's
/// `Calendar(identifier: .chinese)` (ICU), plus the Chinese display names that
/// Foundation does not provide.
public struct LunarDate: Equatable {
    /// Sexagenary (60-year cycle) ordinal, 1...60. 1 == 甲子.
    public let cyclicYear: Int
    /// 1...12, where 1 is 正月. A leap month repeats the previous month's number.
    public let month: Int
    /// 1...30.
    public let day: Int
    /// True when this is an intercalary month (闰月).
    public let isLeapMonth: Bool
    /// Number of days in this lunar month, 29 (小月) or 30 (大月).
    public let daysInMonth: Int

    static let heavenlyStems = ["甲","乙","丙","丁","戊","己","庚","辛","壬","癸"]
    static let earthlyBranches = ["子","丑","寅","卯","辰","巳","午","未","申","酉","戌","亥"]
    static let zodiacAnimals = ["鼠","牛","虎","兔","龙","蛇","马","羊","猴","鸡","狗","猪"]
    static let monthNames = ["正","二","三","四","五","六","七","八","九","十","冬","腊"]
    static let dayNames = [
        "初一","初二","初三","初四","初五","初六","初七","初八","初九","初十",
        "十一","十二","十三","十四","十五","十六","十七","十八","十九","二十",
        "廿一","廿二","廿三","廿四","廿五","廿六","廿七","廿八","廿九","三十",
    ]

    /// e.g. "丙午"
    public var stemBranch: String {
        let i = cyclicYear - 1
        return Self.heavenlyStems[i % 10] + Self.earthlyBranches[i % 12]
    }

    /// e.g. "马"
    public var zodiac: String { Self.zodiacAnimals[(cyclicYear - 1) % 12] }

    /// e.g. "闰五月"
    public var monthName: String {
        (isLeapMonth ? "闰" : "") + Self.monthNames[month - 1] + "月"
    }

    /// e.g. "十一"
    public var dayName: String { Self.dayNames[day - 1] }

    /// What a calendar cell shows when there is no festival or solar term:
    /// the month name on the first day, otherwise the day name.
    public var cellLabel: String { day == 1 ? monthName : dayName }

    /// e.g. "丙午年 八月十一"
    public var fullDescription: String {
        "\(stemBranch)年 \(monthName)\(dayName)"
    }

    /// 除夕 — the last day of the twelfth month.
    public var isNewYearsEve: Bool { month == 12 && !isLeapMonth && day == daysInMonth }

    /// 春节 — the first day of the first month.
    public var isSpringFestival: Bool { month == 1 && !isLeapMonth && day == 1 }
}

public enum LunarConverter {
    /// UTC+8 as a fixed offset — deliberately not `Asia/Shanghai`.
    ///
    /// Both the lunisolar calendar and the solar terms are defined against the
    /// 120°E standard meridian, with no daylight saving. The Olson zone carries
    /// China's historical DST (1940–1942, 1946, 1948–1949, 1986–1991) and the
    /// pre-1928 Shanghai local mean time, which shift a term by an hour and can
    /// push one across midnight into the wrong day — 1990's 夏至, for instance,
    /// lands at 23:32 standard time but 00:32 the next day under DST.
    public static let timeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? .current

    private static let chinese: Calendar = {
        var c = Calendar(identifier: .chinese)
        c.timeZone = timeZone
        return c
    }()

    /// Converts a Gregorian date to its lunar counterpart.
    ///
    /// `date` is treated as *the calendar day the user is looking at*, not as
    /// an absolute instant: its year/month/day are read in the host time zone
    /// and re-anchored to noon in China. Passing a raw instant — a solar term,
    /// say — gives the wrong day whenever the host is west of China and the
    /// instant is near midnight. Convert such instants through a UTC+8
    /// calendar instead.
    public static func lunarDate(from date: Date) -> LunarDate {
        let noon = normalizedToNoon(date)
        let c = chinese.dateComponents([.year, .month, .day, .isLeapMonth], from: noon)
        let days = chinese.range(of: .day, in: .month, for: noon)?.count ?? 30
        return LunarDate(
            cyclicYear: c.year ?? 1,
            month: c.month ?? 1,
            day: c.day ?? 1,
            isLeapMonth: c.isLeapMonth ?? false,
            daysInMonth: days
        )
    }

    /// Re-anchors the instant to noon in China on the *same calendar day* the
    /// user sees locally.
    ///
    /// Lunar month boundaries are defined at midnight in China, while the day a
    /// cell represents is a local calendar day. Reading Y/M/D in the host time
    /// zone and rebuilding it at Chinese noon keeps the two aligned for users
    /// outside CST, and keeps DST from pushing the result into a neighbouring
    /// day.
    private static func normalizedToNoon(_ date: Date) -> Date {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        let ymd = local.dateComponents([.year, .month, .day], from: date)

        var chineseGregorian = Calendar(identifier: .gregorian)
        chineseGregorian.timeZone = timeZone
        return chineseGregorian.date(from: DateComponents(
            year: ymd.year, month: ymd.month, day: ymd.day, hour: 12
        )) ?? date
    }
}
