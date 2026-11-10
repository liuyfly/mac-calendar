// Calendar days as plain integers: the number of days since 1970-01-01.
//
// A cell represents a calendar day, not an instant, so nothing here goes
// through the host time zone. Arithmetic is integer addition, and the only
// conversions are to and from the Y/M/D the user sees.

const MS_PER_DAY = 86400000;

/** Day number for a Gregorian date. `month` is 1...12. */
export function dayNumber(year, month, day) {
  return Math.round(Date.UTC(year, month - 1, day) / MS_PER_DAY);
}

/** `{ year, month, day, weekday }` for a day number; weekday 0 is Sunday. */
export function parts(dn) {
  const d = new Date(dn * MS_PER_DAY);
  return {
    year: d.getUTCFullYear(),
    month: d.getUTCMonth() + 1,
    day: d.getUTCDate(),
    weekday: d.getUTCDay(),
  };
}

/** Today in the device's own time zone. */
export function today(now = new Date()) {
  return dayNumber(now.getFullYear(), now.getMonth() + 1, now.getDate());
}

/** `yyyy-MM-dd`, the key the holiday feeds use. */
export function isoKey(dn) {
  const p = parts(dn);
  return `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
}

/** Number of days in a Gregorian month. */
export function daysInMonth(year, month) {
  return dayNumber(year, month + 1, 1) - dayNumber(year, month, 1);
}

/** ISO 8601 week number: weeks start on Monday, week 1 holds the first Thursday. */
export function isoWeek(dn) {
  const weekday = (parts(dn).weekday + 6) % 7;   // Monday = 0
  const thursday = dn - weekday + 3;
  const year = parts(thursday).year;
  return Math.floor((thursday - dayNumber(year, 1, 1)) / 7) + 1;
}

/** Year and month `delta` months away, as `{ year, month }`. */
export function addMonths(year, month, delta) {
  const index = year * 12 + (month - 1) + delta;
  return { year: Math.floor(index / 12), month: (index % 12 + 12) % 12 + 1 };
}

/** Milliseconds until the next local midnight, for the day rollover timer. */
export function msUntilMidnight(now = new Date()) {
  const next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 5);
  return next - now;
}
