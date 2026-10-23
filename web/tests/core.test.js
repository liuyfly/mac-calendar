// Unit tests for the web core, ported from Tests/CalendarCoreTests.
// Run with: node --test web/tests/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { dayNumber, parts, isoWeek, addMonths, isoKey } from '../core/days.js';
import { lunarDate, stemBranch, zodiac, monthName, dayName, cellLabel, isNewYearsEve } from '../core/lunar.js';
import { termsInYear, termOn, chinaDay, LONGITUDES } from '../core/solar-terms.js';
import { festivalsOn } from '../core/festivals.js';
import { HolidayStore, SOURCES } from '../core/holidays.js';
import { makeMonth, focusedDay, footerTitle, footerDetail } from '../core/calendar.js';

const day = dayNumber;
const names = (dn) => festivalsOn(dn).map((f) => f.name);
const bundled = JSON.parse(readFileSync(
  new URL('../../Sources/CalendarCore/Resources/holidays.json', import.meta.url), 'utf8'));

function bundledStore() {
  const store = new HolidayStore();
  store.loadBundled(bundled);
  return store;
}

const DEFAULT_PREFS = { weekStartsOnMonday: true, showSolarTerms: true, showHolidayBadges: true };

// MARK: - Days

test('days — ISO week and month arithmetic', () => {
  assert.equal(isoWeek(day(2026, 9, 21)), 39);
  assert.equal(isoWeek(day(2027, 1, 1)), 53);        // a Friday, still in 2026's week 53
  assert.equal(isoWeek(day(2026, 1, 1)), 1);
  assert.deepEqual(addMonths(2026, 12, 1), { year: 2027, month: 1 });
  assert.deepEqual(addMonths(2026, 1, -1), { year: 2025, month: 12 });
  assert.deepEqual(addMonths(2026, 3, -27), { year: 2023, month: 12 });
  assert.equal(isoKey(day(2026, 2, 3)), '2026-02-03');
  assert.equal(parts(day(2026, 9, 21)).weekday, 1);
});

// MARK: - Lunar

test('lunar — known conversions', () => {
  const cases = [
    [day(2026, 9, 21), '丙午', '八月十一'],
    [day(2026, 2, 17), '丙午', '正月初一'],   // Spring Festival 2026
    [day(2025, 1, 29), '乙巳', '正月初一'],   // Spring Festival 2025
    [day(2026, 9, 25), '丙午', '八月十五'],   // Mid-Autumn 2026
    [day(2026, 12, 31), '丙午', '冬月廿三'],
  ];
  for (const [dn, sb, label] of cases) {
    const lunar = lunarDate(dn);
    assert.equal(stemBranch(lunar), sb, isoKey(dn));
    assert.equal(monthName(lunar) + dayName(lunar), label, isoKey(dn));
  }
});

test('lunar — zodiac turns at Spring Festival, not 1 Jan', () => {
  assert.equal(zodiac(lunarDate(day(2026, 1, 1))), '蛇');
  assert.equal(zodiac(lunarDate(day(2026, 2, 16))), '蛇');
  assert.equal(zodiac(lunarDate(day(2026, 2, 17))), '马');
});

test('lunar — leap month', () => {
  // 2028 has a leap fifth month.
  const lunar = lunarDate(day(2028, 6, 25));
  assert.ok(lunar.isLeapMonth);
  assert.equal(monthName(lunar), '闰五月');
});

test('lunar — 除夕 tracks a short twelfth month', () => {
  // 2026's twelfth month has 29 days, 2024's has 30.
  assert.ok(isNewYearsEve(day(2026, 2, 16)));
  assert.equal(lunarDate(day(2026, 2, 16)).day, 29);
  assert.ok(!isNewYearsEve(day(2026, 2, 15)));
  assert.ok(isNewYearsEve(day(2024, 2, 9)));
  assert.equal(lunarDate(day(2024, 2, 9)).day, 30);
});

test('lunar — dates where browser ICU builds disagree follow Foundation', () => {
  // Chrome and Node (ICU 78) get each of these wrong; the table must not.
  assert.equal(monthName(lunarDate(day(2027, 2, 6))) + dayName(lunarDate(day(2027, 2, 6))), '正月初一');
  assert.equal(monthName(lunarDate(day(2030, 2, 3))) + dayName(lunarDate(day(2030, 2, 3))), '正月初一');
  assert.equal(monthName(lunarDate(day(2018, 11, 8))) + dayName(lunarDate(day(2018, 11, 8))), '十月初一');
  assert.equal(monthName(lunarDate(day(1987, 7, 26))), '闰六月');
  assert.equal(monthName(lunarDate(day(1987, 8, 24))), '七月');
});

test('lunar — table edges', () => {
  assert.equal(lunarDate(day(1900, 1, 31)).day, 1);              // first day in the table
  assert.equal(stemBranch(lunarDate(day(1900, 1, 31))), '庚子');
  assert.equal(stemBranch(lunarDate(day(2101, 1, 1))), '庚申'); // still lunar 2100
  // Outside the table the browser's ICU answers rather than nothing.
  assert.ok(lunarDate(day(1899, 6, 1)).day >= 1);
  assert.ok(lunarDate(day(2102, 6, 1)).day >= 1);
});

test('lunar — first of month shows the month name', () => {
  assert.equal(cellLabel(lunarDate(day(2026, 9, 11))), '八月');
  assert.equal(cellLabel(lunarDate(day(2026, 9, 21))), '十一');
});

// MARK: - Solar terms

function shanghai(time) {
  const d = new Date(time + 8 * 3600 * 1000);
  return { month: d.getUTCMonth() + 1, day: d.getUTCDate(), minutes: d.getUTCHours() * 60 + d.getUTCMinutes(), year: d.getUTCFullYear() };
}

test('solar terms — published instants', () => {
  // Purple Mountain Observatory tables; tolerance one minute.
  const expected = [
    [2024, '冬至', 12, 21, 17, 20],
    [2024, '立春', 2, 4, 16, 26],
    [2025, '立春', 2, 3, 22, 10],
    [2025, '冬至', 12, 21, 23, 2],
    [2026, '雨水', 2, 18, 23, 51],   // 8 minutes before midnight
    [2026, '秋分', 9, 23, 8, 5],
    [2026, '冬至', 12, 22, 4, 50],
  ];
  for (const [year, name, month, dayOfMonth, hour, minute] of expected) {
    const term = termsInYear(year).find((t) => t.name === name);
    const s = shanghai(term.time);
    assert.equal(s.month, month, `${year} ${name}`);
    assert.equal(s.day, dayOfMonth, `${year} ${name}`);
    assert.ok(Math.abs(s.minutes - (hour * 60 + minute)) <= 1,
      `${year} ${name} off by ${s.minutes - (hour * 60 + minute)} min`);
  }
});

test('solar terms — ordering and spacing, and each stays in its year, 2020–2035', () => {
  for (let year = 2020; year <= 2035; year++) {
    const terms = termsInYear(year);
    assert.equal(terms.length, 24);
    for (let i = 1; i < terms.length; i++) {
      const gap = (terms[i].time - terms[i - 1].time) / 86400000;
      assert.ok(gap > 13.5 && gap < 16.5, `${year} ${terms[i - 1].name}→${terms[i].name} gap ${gap}`);
    }
    for (const term of terms) assert.equal(shanghai(term.time).year, year, `${term.name} escaped ${year}`);
  }
});

test('solar terms — a day maps to its term', () => {
  assert.equal(termOn(day(2026, 2, 18))?.name, '雨水');
  assert.equal(termOn(day(2026, 2, 19)), null);
  assert.equal(termOn(day(2026, 9, 23))?.name, '秋分');
});

/** Meeus ch. 25 low-accuracy formula: shares no coefficients with VSOP87. */
function roughSolarTermTime(year, target) {
  const rad = Math.PI / 180;
  const roughLongitude = (jd) => {
    const t = (jd - 2451545.0) / 36525.0;
    const l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;
    const m = (357.52911 + 35999.05029 * t - 0.0001537 * t * t) * rad;
    const c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * Math.sin(m)
      + (0.019993 - 0.000101 * t) * Math.sin(2 * m) + 0.000289 * Math.sin(3 * m);
    const omega = 125.04 - 1934.136 * t;
    const x = (l0 + c - 0.00569 - 0.00478 * Math.sin(omega * rad)) % 360;
    return x < 0 ? x + 360 : x;
  };
  const wrapped = (d) => { let v = (d + 180) % 360; if (v < 0) v += 360; return v - 180; };
  const offset = (target - 285) % 360 < 0 ? target - 285 + 360 : target - 285;
  let y = year, m = Math.min(12, Math.max(1, Math.floor(offset / 30) + 1));
  if (m <= 2) { y -= 1; m += 12; }
  const a = Math.floor(y / 100), b = 2 - a + Math.floor(a / 4);
  let jd = Math.floor(365.25 * (y + 4716)) + Math.floor(30.6001 * (m + 1)) + 15 + b - 1524.5;
  for (let i = 0; i < 10; i++) {
    const delta = wrapped(roughLongitude(jd) - target);
    if (Math.abs(delta) < 1e-7) break;
    jd -= delta / 0.98564736;
  }
  const t = year - 2000;
  const deltaT = 62.92 + 0.32217 * t + 0.005589 * t * t;
  return ((jd - 2440587.5) * 86400 - deltaT) * 1000;
}

test('solar terms — cross-check against the low-accuracy formula', () => {
  // Guards against a mistyped VSOP87 coefficient.
  for (const year of [2024, 2026, 2030]) {
    for (const term of termsInYear(year)) {
      const minutes = Math.abs(term.time - roughSolarTermTime(year, term.longitude)) / 60000;
      assert.ok(minutes < 20, `${year} ${term.name} differs by ${Math.round(minutes)} min`);
    }
  }
});

test('solar terms agree with the leap months in the lunar table, 1901–2100', () => {
  // A leap month is one holding no 中气 (a term at a multiple of 30°). The
  // table comes from ICU and the VSOP87 series shares no code with it, so
  // this checks one against the other across the whole range.
  let checked = 0;
  const offenders = [];
  for (let year = 1901; year <= 2100; year++) {
    for (const term of termsInYear(year)) {
      if (term.longitude % 30 !== 0) continue;
      checked++;
      const lunar = lunarDate(chinaDay(term.time));
      if (lunar.isLeapMonth) offenders.push(`${year} ${term.name} in leap month ${lunar.month}`);
    }
  }
  assert.equal(checked, 2400, '12 major terms a year over 200 years');
  assert.deepEqual(offenders, []);
  assert.equal(LONGITUDES.length, 24);
});

// MARK: - Festivals

test('festivals — lunar', () => {
  assert.ok(names(day(2026, 2, 17)).includes('春节'));
  assert.ok(names(day(2026, 2, 16)).includes('除夕'));
  assert.ok(names(day(2026, 9, 25)).includes('中秋节'));
  assert.ok(names(day(2026, 6, 19)).includes('端午节'));
  assert.ok(names(day(2026, 3, 3)).includes('元宵节'));
});

test('festivals — Gregorian and floating', () => {
  assert.ok(names(day(2026, 10, 1)).includes('国庆节'));
  assert.ok(names(day(2026, 9, 10)).includes('教师节'));
  assert.ok(names(day(2026, 5, 10)).includes('母亲节'), '2nd Sunday of May 2026');
  assert.ok(!names(day(2026, 5, 3)).includes('母亲节'), '1st Sunday is not 母亲节');
  assert.ok(names(day(2026, 6, 21)).includes('父亲节'), '3rd Sunday of June 2026');
  assert.ok(names(day(2026, 11, 26)).includes('感恩节'), '4th Thursday of November 2026');
});

test('festivals — major outranks minor on the same day', () => {
  // 2018-02-16 is both 春节 (major) and nothing minor, but 2024-02-14 is 情人节
  // and 正月初五; scan for every day that carries both kinds instead.
  let collisions = 0;
  for (let dn = day(2000, 1, 1); dn < day(2050, 1, 1); dn++) {
    const list = festivalsOn(dn);
    if (list.some((f) => f.isMajor) && list.some((f) => !f.isMajor)) {
      collisions++;
      assert.equal(list[0].isMajor, true, isoKey(dn));
    }
  }
  assert.ok(collisions > 0, 'the range should contain at least one collision');
});

// MARK: - Holidays

test('holidays — bundled 2026 arrangement', () => {
  const store = bundledStore();
  assert.ok(store.availableYears.includes(2025));
  assert.ok(store.availableYears.includes(2026));
  assert.deepEqual(store.status(day(2026, 10, 1)), { isOffDay: true, name: '国庆节' });
  assert.equal(store.status(day(2026, 9, 20))?.isOffDay, false, '2026-09-20 is a make-up workday');
  assert.equal(store.status(day(2026, 9, 21)), null);
  assert.notEqual(store.status(day(2026, 2, 17)), null);
});

test('holidays — holiday-cn schema', () => {
  const parse = SOURCES[0].parse;
  const json = { year: 2026, papers: ['https://gov.cn/x'], days: [
    { date: '2026-10-01', isOffDay: true, name: '国庆节' },
    { date: '2026-09-20', isOffDay: false, name: '国庆节' }] };
  const days = parse(json, 2026);
  assert.equal(days.length, 2);
  assert.equal(days.find((d) => d.isOffDay).date, '2026-10-01');
  assert.equal(parse(json, 2027), null, 'payload for another year is rejected');
  assert.equal(parse(null, 2026), null);
  assert.equal(parse({ year: 2026, days: [] }, 2026), null, 'an empty day list is not an update');
});

test('holidays — chinese-days schema', () => {
  const parse = SOURCES[2].parse;
  const json = {
    holidays: { '2026-10-01': 'National Day,国庆节,7', '2026-10-02': 'National Day,国庆节,7' },
    workdays: { '2026-09-20': 'National Day,国庆节,7' },
    inLieuDays: { '2026-10-02': 'National Day,国庆节,7' },
  };
  const days = parse(json, 2026);
  assert.equal(days.length, 3, 'inLieuDays must not add duplicates');
  assert.equal(days.filter((d) => d.isOffDay).length, 2);
  assert.equal(days[0].name, '国庆节');
  assert.deepEqual(days.map((d) => d.date), ['2026-09-20', '2026-10-01', '2026-10-02']);
  assert.equal(parse(json, 2027), null);
});

test('holidays — source order and URLs', () => {
  assert.equal(SOURCES.length, 3);
  assert.match(SOURCES[0].url(2027), /holiday-cn@master\/2027\.json$/);
  assert.match(SOURCES[1].url(2027), /raw\.githubusercontent/);
  assert.match(SOURCES[2].url(2027), /chinese-days/);
  for (const s of SOURCES) assert.ok(s.url(2026).startsWith('https://'));
});

function memoryStorage() {
  const map = new Map();
  return {
    get length() { return map.size; },
    key: (i) => [...map.keys()][i] ?? null,
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
  };
}

const response = (status, body) => ({ ok: status === 200, status, json: async () => body });

test('holidays — refresh falls back through sources, caches, and throttles', async () => {
  const storage = memoryStorage();
  const store = new HolidayStore(storage);
  const now = new Date(2026, 9, 23, 9);
  const requested = [];
  const fetchImpl = async (url) => {
    requested.push(url);
    if (url.includes('jsdelivr.net/gh')) return response(404, null);   // first CDN down
    if (url.includes('raw.githubusercontent') && url.endsWith('2026.json')) {
      return response(200, { year: 2026, days: [{ date: '2026-12-31', isOffDay: true, name: '测试' }] });
    }
    return response(404, null);                                         // 2027 not published
  };

  assert.deepEqual(await store.refresh({ now, fetchImpl }), [2026]);
  assert.deepEqual(store.status(day(2026, 12, 31)), { isOffDay: true, name: '测试' });
  assert.equal(requested.filter((u) => u.includes('2027')).length, 3, '2027 walks every source');

  // A fresh store reads the cached year back.
  const reloaded = new HolidayStore(storage);
  reloaded.loadBundled(bundled);
  reloaded.loadCached();
  assert.equal(reloaded.status(day(2026, 12, 31))?.name, '测试');
  assert.equal(reloaded.status(day(2026, 10, 1)), null, 'the download replaces the bundled year');

  // Within 12 hours a launch check is skipped; a forced one is not.
  requested.length = 0;
  assert.deepEqual(await store.refresh({ now: new Date(now.getTime() + 3600000), fetchImpl }), []);
  assert.equal(requested.length, 0);
  await store.refresh({ now, fetchImpl, force: true });
  assert.ok(requested.length > 0);
  assert.match(store.coverageSummary(), /^已覆盖 2026 年 · 上次更新 10月23日$/);
});

test('holidays — a network failure is silent', async () => {
  const store = new HolidayStore(memoryStorage());
  const fetchImpl = async () => { throw new TypeError('offline'); };
  assert.deepEqual(await store.refresh({ fetchImpl }), []);
  assert.equal(HolidayStore.refreshResultMessage([]), '更新失败，继续使用现有数据');
  assert.equal(HolidayStore.refreshResultMessage([2026, 2027]), '已更新 2026、2027 年');
});

// MARK: - Month grid

test('month — grid shape', () => {
  const holidays = bundledStore();
  for (let month = 1; month <= 12; month++) {
    const grid = makeMonth(2026, month, { today: day(2026, 9, 21), prefs: DEFAULT_PREFS, holidays });
    assert.equal(grid.days.length, 42);
    assert.ok(grid.days.some((d) => d.day === 1 && d.inMonth));
  }
  const feb = makeMonth(2028, 2, { today: 0, prefs: DEFAULT_PREFS, holidays });
  assert.equal(feb.days.filter((d) => d.inMonth).length, 29);
});

test('month — week start', () => {
  // 2026-09-01 is a Tuesday.
  const monday = makeMonth(2026, 9, { today: 0, prefs: DEFAULT_PREFS, holidays: null });
  assert.equal(monday.days[0].day, 31);
  assert.equal(monday.weekdaySymbols[0], '一');
  const sunday = makeMonth(2026, 9, { today: 0, prefs: { ...DEFAULT_PREFS, weekStartsOnMonday: false }, holidays: null });
  assert.equal(sunday.days[0].day, 30);
  assert.equal(sunday.weekdaySymbols[0], '日');
});

test('month — September 2026 renders as designed', () => {
  const grid = makeMonth(2026, 9, { today: day(2026, 9, 21), prefs: DEFAULT_PREFS, holidays: bundledStore() });
  const byDay = new Map(grid.days.filter((d) => d.inMonth).map((d) => [d.day, d]));
  assert.deepEqual(byDay.get(7).subtitle, { kind: 'term', text: '白露' });
  assert.deepEqual(byDay.get(11).subtitle, { kind: 'lunar', text: '八月' });
  assert.deepEqual(byDay.get(21).subtitle, { kind: 'lunar', text: '十一' });
  assert.deepEqual(byDay.get(23).subtitle, { kind: 'term', text: '秋分' });
  assert.deepEqual(byDay.get(25).subtitle, { kind: 'festival', text: '中秋节' });
  assert.ok(byDay.get(21).isToday);
  assert.equal(byDay.get(20).holiday?.isOffDay, false, '2026-09-20 carries a 班 badge');
  assert.equal(grid.yearSummary, '丙午 马年');
  assert.equal(grid.lunarMonthSummary, '七月—八月');
});

test('month — preferences turn terms and badges off', () => {
  const prefs = { weekStartsOnMonday: true, showSolarTerms: false, showHolidayBadges: false };
  const grid = makeMonth(2026, 9, { today: 0, prefs, holidays: bundledStore() });
  const byDay = new Map(grid.days.filter((d) => d.inMonth).map((d) => [d.day, d]));
  assert.equal(byDay.get(23).subtitle.kind, 'lunar');
  assert.equal(byDay.get(20).holiday, null);
});

test('footer — title and detail', () => {
  const grid = makeMonth(2026, 9, { today: day(2026, 9, 21), prefs: DEFAULT_PREFS, holidays: bundledStore() });
  const today = focusedDay(grid, null);
  assert.equal(footerTitle(today), '2026年9月21日 星期一');
  assert.equal(footerDetail(today), '丙午年 八月十一 · 第 39 周 · 距中秋节还有 4 天');

  const workday = focusedDay(grid, day(2026, 9, 20));
  assert.match(footerDetail(workday), / · 调休上班$/);

  // Today not on screen: the 1st of the month.
  const october = makeMonth(2026, 10, { today: day(2026, 9, 21), prefs: DEFAULT_PREFS, holidays: null });
  assert.equal(footerTitle(focusedDay(october, null)), '2026年10月1日 星期四');
});
