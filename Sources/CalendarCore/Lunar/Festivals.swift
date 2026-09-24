import Foundation

/// A named day worth showing in place of the plain lunar date.
public struct Festival: Equatable {
    public enum Kind {
        /// Lunar-calendar festivals: 春节, 中秋 …
        case lunar
        /// Fixed Gregorian dates: 元旦, 国庆节 …
        case gregorian
        /// Nth-weekday-of-month festivals: 母亲节, 父亲节 …
        case floating
    }
    public let name: String
    public let kind: Kind
    /// Major festivals outrank minor ones when several land on the same day.
    public let isMajor: Bool
}

public enum Festivals {

    // MARK: - Tables

    /// Keyed by `month * 100 + day` in the lunar calendar.
    private static let lunarTable: [Int: (String, Bool)] = [
        101: ("春节", true),
        115: ("元宵节", true),
        202: ("龙抬头", false),
        303: ("上巳节", false),
        505: ("端午节", true),
        707: ("七夕节", false),
        715: ("中元节", false),
        815: ("中秋节", true),
        909: ("重阳节", false),
        1008: ("寒衣节", false),
        1208: ("腊八节", false),
        1223: ("北方小年", false),
        1224: ("南方小年", false),
    ]

    /// Keyed by `month * 100 + day` in the Gregorian calendar.
    private static let gregorianTable: [Int: (String, Bool)] = [
        101: ("元旦", true),
        214: ("情人节", false),
        308: ("妇女节", false),
        312: ("植树节", false),
        401: ("愚人节", false),
        501: ("劳动节", true),
        504: ("青年节", false),
        601: ("儿童节", false),
        701: ("建党节", false),
        801: ("建军节", false),
        910: ("教师节", false),
        1001: ("国庆节", true),
        1031: ("万圣夜", false),
        1224: ("平安夜", false),
        1225: ("圣诞节", false),
    ]

    /// `(month, weekday, ordinal, name)` where weekday is 1 = Sunday and a
    /// negative ordinal counts back from the end of the month.
    private static let floatingTable: [(month: Int, weekday: Int, ordinal: Int, name: String)] = [
        (5, 1, 2, "母亲节"),
        (6, 1, 3, "父亲节"),
        (11, 5, 4, "感恩节"),
    ]

    // MARK: - Lookup

    /// Every festival falling on `date`, most important first.
    public static func festivals(on date: Date, lunar: LunarDate) -> [Festival] {
        var found: [Festival] = []

        // 除夕 is not a fixed lunar date — the twelfth month may end on the
        // 29th or the 30th — so it is derived rather than tabled.
        if lunar.isNewYearsEve {
            found.append(Festival(name: "除夕", kind: .lunar, isMajor: true))
        }
        if !lunar.isLeapMonth, let entry = lunarTable[lunar.month * 100 + lunar.day] {
            found.append(Festival(name: entry.0, kind: .lunar, isMajor: entry.1))
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .weekday, .weekdayOrdinal], from: date)
        guard let month = parts.month, let day = parts.day else { return found }

        if let entry = gregorianTable[month * 100 + day] {
            found.append(Festival(name: entry.0, kind: .gregorian, isMajor: entry.1))
        }

        if let weekday = parts.weekday, let ordinal = parts.weekdayOrdinal {
            for rule in floatingTable where rule.month == month
                && rule.weekday == weekday && rule.ordinal == ordinal {
                found.append(Festival(name: rule.name, kind: .floating, isMajor: false))
            }
        }

        return found.sorted { lhs, rhs in
            lhs.isMajor && !rhs.isMajor
        }
    }
}
