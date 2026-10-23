// The Chinese lunisolar calendar, from a table exported from Foundation's
// `Calendar(identifier: .chinese)` — the source the native apps read — so
// every browser shows the same dates as they do. See lunar-table.js.

import { parts, dayNumber } from './days.js';
import { FIRST_YEAR, YEARS } from './lunar-table.js';

const HEAVENLY_STEMS = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
const EARTHLY_BRANCHES = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
const ZODIAC_ANIMALS = ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'];
const MONTH_NAMES = ['正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '冬', '腊'];
const DAY_NAMES = [
  '初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
  '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
  '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十',
];

const LAST_YEAR = FIRST_YEAR + YEARS.length - 1;

/** Day number of 正月初一 in a lunar year covered by the table. */
function newYear(year) {
  return dayNumber(year, 1, 1) + (YEARS[year - FIRST_YEAR] >> 17);
}

// Outside the table, fall back to the browser's ICU. Engines disagree on a
// handful of dates, but only far from today. UTC+8 as a fixed offset, not
// Asia/Shanghai, which carries China's historical DST.
let intlFormatter = null;

function intlLunarDate(dn) {
  intlFormatter ??= new Intl.DateTimeFormat('en-u-ca-chinese', {
    timeZone: 'Etc/GMT-8', year: 'numeric', month: 'numeric', day: 'numeric',
  });
  const p = parts(dn);
  const fields = {};
  for (const part of intlFormatter.formatToParts(Date.UTC(p.year, p.month - 1, p.day, 4))) {
    fields[part.type] = part.value;
  }
  // ICU marks a leap month with a suffix: "6bis" is 闰六月.
  return {
    year: parseInt(fields.relatedYear ?? fields.year, 10),
    month: parseInt(fields.month, 10),
    day: parseInt(fields.day, 10),
    isLeapMonth: /bis/.test(fields.month),
  };
}

function tableLunarDate(dn) {
  // Early in a Gregorian year, the day still belongs to the previous lunar year.
  let year = parts(dn).year;
  if (year > LAST_YEAR) year = LAST_YEAR;
  else if (year >= FIRST_YEAR && dn < newYear(year)) year -= 1;
  if (year < FIRST_YEAR) return null;

  const entry = YEARS[year - FIRST_YEAR];
  const leapMonth = (entry >> 13) & 0xf;
  const monthCount = leapMonth ? 13 : 12;
  let remaining = dn - newYear(year);
  for (let i = 0; i < monthCount; i++) {
    const length = entry & (1 << i) ? 30 : 29;
    if (remaining < length) {
      // With a leap month, the sequence runs 1 … leapMonth, 闰leapMonth, …
      const isLeapMonth = leapMonth !== 0 && i === leapMonth;
      const month = leapMonth !== 0 && i >= leapMonth ? i : i + 1;
      return { year, month, day: remaining + 1, isLeapMonth };
    }
    remaining -= length;
  }
  return null;   // past the end of the last year in the table
}

const cache = new Map();

/**
 * The lunar date of a calendar day.
 *
 * Returns `{ cyclicYear, month, day, isLeapMonth }` where `cyclicYear` is the
 * sexagenary ordinal 1...60 (1 = 甲子) and a leap month repeats the previous
 * month's number.
 */
export function lunarDate(dn) {
  let result = cache.get(dn);
  if (result) return result;
  const raw = tableLunarDate(dn) ?? intlLunarDate(dn);
  result = Object.freeze({
    cyclicYear: ((raw.year - 4) % 60 + 60) % 60 + 1,
    month: raw.month,
    day: raw.day,
    isLeapMonth: raw.isLeapMonth,
  });
  cache.set(dn, result);
  return result;
}

/** e.g. "丙午" */
export function stemBranch(lunar) {
  const i = lunar.cyclicYear - 1;
  return HEAVENLY_STEMS[i % 10] + EARTHLY_BRANCHES[i % 12];
}

/** e.g. "马" */
export function zodiac(lunar) {
  return ZODIAC_ANIMALS[(lunar.cyclicYear - 1) % 12];
}

/** e.g. "闰五月" */
export function monthName(lunar) {
  return (lunar.isLeapMonth ? '闰' : '') + MONTH_NAMES[lunar.month - 1] + '月';
}

/** e.g. "十一" */
export function dayName(lunar) {
  return DAY_NAMES[lunar.day - 1];
}

/** What a cell shows when there is no festival or term: the month name on the 1st. */
export function cellLabel(lunar) {
  return lunar.day === 1 ? monthName(lunar) : dayName(lunar);
}

/** e.g. "丙午年 八月十一" */
export function fullDescription(lunar) {
  return `${stemBranch(lunar)}年 ${monthName(lunar)}${dayName(lunar)}`;
}

/**
 * 除夕 — the last day of the twelfth month. The month may end on the 29th or
 * the 30th, so it is the day before 正月初一 rather than a fixed date.
 */
export function isNewYearsEve(dn) {
  const lunar = lunarDate(dn);
  if (lunar.month !== 12 || lunar.isLeapMonth || lunar.day < 29) return false;
  const next = lunarDate(dn + 1);
  return next.month === 1 && next.day === 1 && !next.isLeapMonth;
}
