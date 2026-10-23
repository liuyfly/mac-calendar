// The 24 solar terms (节气), from a truncated VSOP87D series for Earth's
// heliocentric longitude. A port of SolarTerms.swift.
//
// A term falls on whatever Chinese calendar day contains the instant the sun
// reaches a multiple of 15° of apparent longitude, so accuracy matters near
// midnight: 2026's 雨水 lands at 23:51. The series is good to ~1″ (~25
// seconds of solar motion), which keeps the day assignment unambiguous.

import { EARTH_L, EARTH_R } from './vsop87.js';
import { parts, dayNumber } from './days.js';

/** Traditional order, starting from 小寒 — the first term of the Gregorian year. */
export const NAMES = [
  '小寒', '大寒', '立春', '雨水', '惊蛰', '春分', '清明', '谷雨',
  '立夏', '小满', '芒种', '夏至', '小暑', '大暑', '立秋', '处暑',
  '白露', '秋分', '寒露', '霜降', '立冬', '小雪', '大雪', '冬至',
];

/** Apparent solar longitude for each term, matching NAMES. */
export const LONGITUDES = NAMES.map((_, i) => (i * 15 + 285) % 360);

const CHINA_OFFSET_MS = 8 * 3600 * 1000;

const yearCache = new Map();
const dayCache = new Map();

/**
 * All 24 terms falling inside a Gregorian year, in chronological order, as
 * `{ name, longitude, time }` with `time` in epoch milliseconds. Cached per
 * year; the series is far too heavy to run per cell.
 */
export function termsInYear(year) {
  let terms = yearCache.get(year);
  if (!terms) {
    terms = NAMES.map((name, index) => ({
      name,
      longitude: LONGITUDES[index],
      time: solve(year, index),
    }));
    yearCache.set(year, terms);
  }
  return terms;
}

/** The calendar day in China (UTC+8) that an instant falls on. */
export function chinaDay(time) {
  const d = new Date(time + CHINA_OFFSET_MS);
  return dayNumber(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate());
}

/** The term falling on a calendar day, if any. */
export function termOn(dn) {
  const year = parts(dn).year;
  let byDay = dayCache.get(year);
  if (!byDay) {
    byDay = new Map(termsInYear(year).map((term) => [chinaDay(term.time), term]));
    dayCache.set(year, byDay);
  }
  return byDay.get(dn) ?? null;
}

// MARK: - Root finding

/**
 * Newton's method on apparent solar longitude. The sun moves ~0.9856°/day,
 * which is a good enough derivative for the handful of iterations needed.
 */
function solve(year, termIndex) {
  const target = LONGITUDES[termIndex];
  // Each pair of terms falls in one Gregorian month; seed near its middle.
  const seedMonth = Math.floor(termIndex / 2) + 1;
  let jde = julianDay(year, seedMonth, 15.0);

  for (let i = 0; i < 8; i++) {
    const delta = normalizedDegrees(apparentSolarLongitude(jde) - target);
    if (Math.abs(delta) < 1e-7) break;
    jde -= delta / 0.98564736;
  }
  // jde is in Terrestrial Time; the published tables are civil time.
  const jd = jde - deltaTSeconds(year) / 86400.0;
  return (jd - 2440587.5) * 86400000;
}

// MARK: - Solar position

/**
 * Apparent geocentric longitude of the sun, in degrees, for a Julian
 * Ephemeris Day. Meeus, *Astronomical Algorithms*, ch. 25 (high accuracy).
 */
export function apparentSolarLongitude(jde) {
  const tau = (jde - 2451545.0) / 365250.0;   // Julian millennia
  const t = tau * 10.0;                        // Julian centuries

  const l = series(EARTH_L, tau);              // heliocentric longitude, rad
  const r = series(EARTH_R, tau);              // radius vector, AU

  // Geocentric longitude, converted from the VSOP87 dynamical frame to FK5.
  let theta = normalizedDegrees360(degrees(l) + 180.0);
  theta += -0.09033 / 3600.0;

  // Nutation in longitude, principal terms (Meeus 22.x), good to ~0.5".
  const omega = 125.04452 - 1934.136261 * t;
  const lSun = 280.4665 + 36000.7698 * t;
  const lMoon = 218.3165 + 481267.8813 * t;
  const nutation = (-17.20 * Math.sin(radians(omega))
    - 1.32 * Math.sin(radians(2 * lSun))
    - 0.23 * Math.sin(radians(2 * lMoon))
    + 0.21 * Math.sin(radians(2 * omega))) / 3600.0;

  // Annual aberration.
  const aberration = -20.4898 / r / 3600.0;

  return normalizedDegrees360(theta + nutation + aberration);
}

/** Evaluates a VSOP87 series: sum over powers of tau of sum(A cos(B + C tau)). */
function series(table, tau) {
  let total = 0.0;
  table.forEach((terms, power) => {
    let sum = 0.0;
    for (const [a, b, c] of terms) sum += a * Math.cos(b + c * tau);
    total += sum * Math.pow(tau, power);
  });
  return total / 1e8;
}

// MARK: - Time scales

/** TT − UT, in seconds. Espenak & Meeus polynomial for 2005–2050. */
function deltaTSeconds(year) {
  const t = year - 2000.0;
  if (year >= 2005 && year <= 2050) {
    return 62.92 + 0.32217 * t + 0.005589 * t * t;
  }
  const u = (year - 1820.0) / 100.0;
  if (year > 2050 && year <= 2150) {
    return -20 + 32 * u * u - 0.5628 * (2150 - year);
  }
  return -20 + 32 * u * u;
}

export function julianDay(year, month, day) {
  let y = year, m = month;
  if (m <= 2) { y -= 1; m += 12; }
  const a = Math.floor(y / 100.0);
  const b = 2 - a + Math.floor(a / 4.0);
  return Math.floor(365.25 * (y + 4716)) + Math.floor(30.6001 * (m + 1)) + day + b - 1524.5;
}

// MARK: - Angles

function radians(d) { return d * Math.PI / 180.0; }
function degrees(r) { return r * 180.0 / Math.PI; }

/** Wraps to [0, 360). */
function normalizedDegrees360(d) {
  const x = d % 360.0;
  return x < 0 ? x + 360.0 : x;
}

/** Wraps to [-180, 180), so the 0°/360° seam does not break Newton's method. */
function normalizedDegrees(d) {
  return normalizedDegrees360(d + 180.0) - 180.0;
}
