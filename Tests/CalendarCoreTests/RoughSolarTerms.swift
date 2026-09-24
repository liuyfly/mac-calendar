import Foundation

/// An independent, deliberately simple solar term calculation used only to
/// cross-check the production VSOP87 series.
///
/// This is the low-accuracy formula from Meeus ch. 25 — good to about 0.01°,
/// or ~15 minutes of solar motion. It is not accurate enough to ship, but it
/// shares no coefficients with the truncated VSOP87 tables, so a typo in those
/// hundreds of numbers shows up here as a large disagreement.
func roughSolarTermDate(year: Int, longitude target: Double) -> Date {
    func roughLongitude(_ jd: Double) -> Double {
        let t = (jd - 2451545.0) / 36525.0
        let l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t
        let m = 357.52911 + 35999.05029 * t - 0.0001537 * t * t
        let mRad = m * .pi / 180
        let c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(mRad)
            + (0.019993 - 0.000101 * t) * sin(2 * mRad)
            + 0.000289 * sin(3 * mRad)
        let omega = 125.04 - 1934.136 * t
        let apparent = l0 + c - 0.00569 - 0.00478 * sin(omega * .pi / 180)
        return apparent.truncatingRemainder(dividingBy: 360) < 0
            ? apparent.truncatingRemainder(dividingBy: 360) + 360
            : apparent.truncatingRemainder(dividingBy: 360)
    }

    func wrapped(_ degrees: Double) -> Double {
        var value = (degrees + 180).truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value - 180
    }

    // Seed at the middle of the month the term belongs to.
    let monthGuess = Int((target - 285).truncatingRemainder(dividingBy: 360) < 0
        ? (target - 285) + 360 : (target - 285)) / 30 + 1
    var y = year, m = min(12, max(1, monthGuess))
    if m <= 2 { y -= 1; m += 12 }
    let a = Int(floor(Double(y) / 100.0))
    let b = 2 - a + Int(floor(Double(a) / 4.0))
    var jd = floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1))
        + 15.0 + Double(b) - 1524.5

    for _ in 0..<10 {
        let delta = wrapped(roughLongitude(jd) - target)
        if abs(delta) < 1e-7 { break }
        jd -= delta / 0.98564736
    }

    // Same ΔT model as the production path, so the comparison isolates the
    // solar position rather than the time scale.
    let t = Double(year) - 2000.0
    let deltaT = 62.92 + 0.32217 * t + 0.005589 * t * t
    return Date(timeIntervalSince1970: (jd - 2440587.5) * 86400.0 - deltaT)
}
