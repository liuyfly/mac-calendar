import Foundation

/// One of the 24 solar terms (节气).
struct SolarTerm: Equatable {
    let name: String
    /// Apparent solar longitude that defines the term, in degrees.
    let longitude: Double
    /// The instant the sun reaches `longitude`, in Asia/Shanghai.
    let date: Date
}

/// Solar term calculation via a truncated VSOP87D series for Earth's
/// heliocentric longitude.
///
/// A term falls on whatever Chinese calendar day contains the instant the sun
/// reaches a multiple of 15° of apparent longitude, so accuracy matters near
/// midnight: 2026's 雨水 lands at 23:46, only 14 minutes from rolling over.
/// The low-accuracy formula in Meeus ch. 25 is good to ~0.01° (~14 minutes of
/// solar motion) and would be a coin flip there. This series is good to ~1″
/// (~25 seconds), which keeps the day assignment unambiguous.
enum SolarTerms {

    /// Traditional order, starting from 小寒 — the first term of the Gregorian year.
    static let names = [
        "小寒","大寒","立春","雨水","惊蛰","春分","清明","谷雨",
        "立夏","小满","芒种","夏至","小暑","大暑","立秋","处暑",
        "白露","秋分","寒露","霜降","立冬","小雪","大雪","冬至",
    ]

    /// Apparent solar longitude for each term, matching `names`.
    static let longitudes: [Double] = (0..<24).map { Double(($0 * 15 + 285) % 360) }

    // MARK: - Public API

    /// All 24 terms falling inside the given Gregorian year, in chronological order.
    /// Results are cached per year; the series is far too heavy to run per cell.
    static func terms(inYear year: Int) -> [SolarTerm] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[year] { return cached }
        let computed = (0..<24).map { index -> SolarTerm in
            SolarTerm(
                name: names[index],
                longitude: longitudes[index],
                date: solve(year: year, termIndex: index)
            )
        }
        cache[year] = computed
        return computed
    }

    /// The term falling on `date`, if any.
    static func term(on date: Date) -> SolarTerm? {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        let ymd = local.dateComponents([.year, .month, .day], from: date)
        guard let year = ymd.year else { return nil }

        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = LunarConverter.timeZone
        return terms(inYear: year).first { term in
            let t = shanghai.dateComponents([.year, .month, .day], from: term.date)
            return t.year == ymd.year && t.month == ymd.month && t.day == ymd.day
        }
    }

    private nonisolated(unsafe) static var cache: [Int: [SolarTerm]] = [:]
    private static let cacheLock = NSLock()

    // MARK: - Root finding

    /// Newton's method on apparent solar longitude. The sun moves ~0.9856°/day,
    /// which is a good enough derivative for the handful of iterations needed.
    private static func solve(year: Int, termIndex: Int) -> Date {
        let target = longitudes[termIndex]
        // Each pair of terms falls in one Gregorian month; seed near its middle.
        let seedMonth = termIndex / 2 + 1
        var jde = julianDay(year: year, month: seedMonth, day: 15.0)

        for _ in 0..<8 {
            let delta = normalizedDegrees(apparentSolarLongitude(jde) - target)
            if abs(delta) < 1e-7 { break }
            jde -= delta / 0.98564736
        }
        // jde is in Terrestrial Time; the published tables are civil time.
        let jd = jde - deltaTSeconds(year: year) / 86400.0
        return date(fromJulianDay: jd)
    }

    // MARK: - Solar position

    /// Apparent geocentric longitude of the sun, in degrees, for a Julian
    /// Ephemeris Day. Meeus, *Astronomical Algorithms*, ch. 25 (high accuracy).
    static func apparentSolarLongitude(_ jde: Double) -> Double {
        let tau = (jde - 2451545.0) / 365250.0          // Julian millennia
        let t = tau * 10.0                               // Julian centuries

        let l = series(Self.earthL, tau)                 // heliocentric longitude, rad
        let r = series(Self.earthR, tau)                 // radius vector, AU

        var theta = degrees(l) + 180.0                   // geocentric longitude
        theta = normalizedDegrees360(theta)

        // Convert from the VSOP87 dynamical frame to FK5.
        let lPrime = theta - 1.397 * t - 0.00031 * t * t
        theta += -0.09033 / 3600.0
        _ = lPrime  // the latitude correction is not needed for longitude alone

        // Nutation in longitude, principal terms (Meeus 22.x), good to ~0.5".
        let omega = 125.04452 - 1934.136261 * t
        let lSun = 280.4665 + 36000.7698 * t
        let lMoon = 218.3165 + 481267.8813 * t
        let nutation = (-17.20 * sin(radians(omega))
                        - 1.32 * sin(radians(2 * lSun))
                        - 0.23 * sin(radians(2 * lMoon))
                        + 0.21 * sin(radians(2 * omega))) / 3600.0

        // Annual aberration.
        let aberration = -20.4898 / r / 3600.0

        return normalizedDegrees360(theta + nutation + aberration)
    }

    /// Evaluates a VSOP87 series: sum over powers of tau of sum(A cos(B + C tau)).
    private static func series(_ table: [[[Double]]], _ tau: Double) -> Double {
        var total = 0.0
        for (power, terms) in table.enumerated() {
            var sum = 0.0
            for term in terms {
                sum += term[0] * cos(term[1] + term[2] * tau)
            }
            total += sum * pow(tau, Double(power))
        }
        return total / 1e8
    }

    // MARK: - Time scales

    /// TT − UT, in seconds. Espenak & Meeus polynomial for 2005–2050.
    private static func deltaTSeconds(year: Int) -> Double {
        let t = Double(year) - 2000.0
        if year >= 2005 && year <= 2050 {
            return 62.92 + 0.32217 * t + 0.005589 * t * t
        }
        if year > 2050 && year <= 2150 {
            let u = (Double(year) - 1820.0) / 100.0
            return -20 + 32 * u * u - 0.5628 * (2150 - Double(year))
        }
        let u = (Double(year) - 1820.0) / 100.0
        return -20 + 32 * u * u
    }

    private static func julianDay(year: Int, month: Int, day: Double) -> Double {
        var y = year, m = month
        if m <= 2 { y -= 1; m += 12 }
        let a = Int(floor(Double(y) / 100.0))
        let b = 2 - a + Int(floor(Double(a) / 4.0))
        return floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1))
            + day + Double(b) - 1524.5
    }

    private static func date(fromJulianDay jd: Double) -> Date {
        Date(timeIntervalSince1970: (jd - 2440587.5) * 86400.0)
    }

    // MARK: - Angles

    private static func radians(_ d: Double) -> Double { d * .pi / 180.0 }
    private static func degrees(_ r: Double) -> Double { r * 180.0 / .pi }

    /// Wraps to [0, 360).
    private static func normalizedDegrees360(_ d: Double) -> Double {
        let x = d.truncatingRemainder(dividingBy: 360.0)
        return x < 0 ? x + 360.0 : x
    }

    /// Wraps to [-180, 180), so the 0°/360° seam does not break Newton's method.
    private static func normalizedDegrees(_ d: Double) -> Double {
        normalizedDegrees360(d + 180.0) - 180.0
    }
}
