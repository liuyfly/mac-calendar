// The month grid and the details of a day. A port of CalendarMonth.swift,
// DayInfo.swift and the footer half of CalendarViewModel.swift.

import { dayNumber, parts, isoWeek } from './days.js';
import { lunarDate, cellLabel, fullDescription, monthName, stemBranch, zodiac } from './lunar.js';
import { termOn } from './solar-terms.js';
import { festivalsOn } from './festivals.js';

export const ROWS = 6;
export const COLUMNS = 7;

const MONDAY_FIRST = ['一', '二', '三', '四', '五', '六', '日'];
const SUNDAY_FIRST = ['日', '一', '二', '三', '四', '五', '六'];
const WEEKDAY_NAMES = ['日', '一', '二', '三', '四', '五', '六'];

/**
 * Everything one cell needs to render itself.
 *
 * @param options `{ displayedMonth, today, showSolarTerms, holidays }`, where
 *   `holidays` is a HolidayStore or null to show no badges.
 */
export function dayInfo(dn, { displayedMonth = null, today = null, showSolarTerms = true, holidays = null } = {}) {
  const p = parts(dn);
  const lunar = lunarDate(dn);
  const term = showSolarTerms ? termOn(dn) : null;
  const festivals = festivalsOn(dn);
  return {
    dn,
    day: p.day,
    weekday: p.weekday,
    lunar,
    term,
    festivals,
    holiday: holidays ? holidays.status(dn) : null,
    inMonth: displayedMonth === null || p.month === displayedMonth,
    isToday: dn === today,
    isWeekend: p.weekday === 0 || p.weekday === 6,
    subtitle: subtitle(lunar, term, festivals),
  };
}

/**
 * What the secondary line shows, as `{ kind, text }` with kind one of
 * `festival`, `term` or `lunar`.
 *
 * Priority: major festival > solar term > minor festival > lunar date. 清明 is
 * both a term and a statutory festival, and reads better in the festival
 * colour.
 */
function subtitle(lunar, term, festivals) {
  const major = festivals.find((f) => f.isMajor);
  if (major) return { kind: 'festival', text: major.name };
  if (term?.name === '清明') return { kind: 'festival', text: term.name };
  if (term) return { kind: 'term', text: term.name };
  if (festivals.length > 0) return { kind: 'festival', text: festivals[0].name };
  return { kind: 'lunar', text: cellLabel(lunar) };
}

/** e.g. "丙午年 八月十一 · 秋分 · 中秋节" */
export function detailLine(info) {
  const out = [fullDescription(info.lunar)];
  if (info.term) out.push(info.term.name);
  if (info.festivals.length > 0) out.push(info.festivals.map((f) => f.name).join(' · '));
  return out.join(' · ');
}

/**
 * A 6 x 7 grid for one month, padded with the tail of the previous month and
 * the head of the next so every month occupies the same height.
 *
 * @param prefs `{ weekStartsOnMonday, showSolarTerms, showHolidayBadges }`
 */
export function makeMonth(year, month, { today, prefs, holidays }) {
  const first = dayNumber(year, month, 1);
  const firstWeekday = prefs.weekStartsOnMonday ? 1 : 0;
  const offset = (parts(first).weekday - firstWeekday + 7) % 7;
  const gridStart = first - offset;

  const options = {
    displayedMonth: month,
    today,
    showSolarTerms: prefs.showSolarTerms,
    holidays: prefs.showHolidayBadges ? holidays : null,
  };
  const days = [];
  for (let i = 0; i < ROWS * COLUMNS; i++) days.push(dayInfo(gridStart + i, options));

  const inMonth = days.filter((d) => d.inMonth);
  const lunarMonths = [...new Set(inMonth.map((d) => monthName(d.lunar)))];
  const firstLunar = inMonth[0].lunar;

  return {
    year,
    month,
    days,
    weekdaySymbols: prefs.weekStartsOnMonday ? MONDAY_FIRST : SUNDAY_FIRST,
    /** Which header columns are Saturday and Sunday. */
    weekendColumns: prefs.weekStartsOnMonday ? [5, 6] : [0, 6],
    /** e.g. "八月—九月" */
    lunarMonthSummary: lunarMonths.join('—'),
    /** e.g. "丙午 马年" */
    yearSummary: `${stemBranch(firstLunar)} ${zodiac(firstLunar)}年`,
  };
}

/**
 * The day the footer describes: the selection if it is on screen, else today
 * if it is in this month, else the 1st.
 */
export function focusedDay(month, selected) {
  return month.days.find((d) => d.dn === selected)
    ?? month.days.find((d) => d.isToday && d.inMonth)
    ?? month.days.find((d) => d.inMonth);
}

/** e.g. "2026年9月21日 星期一" */
export function footerTitle(info) {
  const p = parts(info.dn);
  return `${p.year}年${p.month}月${p.day}日 星期${WEEKDAY_NAMES[p.weekday]}`;
}

/** e.g. "丙午年 八月十一 · 第 39 周 · 距中秋节还有 4 天" */
export function footerDetail(info) {
  const out = [detailLine(info), `第 ${isoWeek(info.dn)} 周`];
  const next = nextMajorEvent(info.dn);
  if (next) out.push(next);
  if (info.holiday && !info.holiday.isOffDay) out.push('调休上班');
  return out.join(' · ');
}

/**
 * "距中秋节还有 4 天" — the next major festival. Scans a bounded number of
 * days so a stretch with no entry simply yields nothing.
 */
function nextMajorEvent(dn) {
  for (let offset = 1; offset <= 200; offset++) {
    const major = festivalsOn(dn + offset).find((f) => f.isMajor);
    if (major) return `距${major.name}还有 ${offset} 天`;
  }
  return null;
}
