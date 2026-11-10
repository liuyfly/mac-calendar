// Named days worth showing in place of the plain lunar date. A port of
// Festivals.swift.

import { parts } from './days.js';
import { lunarDate, isNewYearsEve } from './lunar.js';

/** Keyed by `month * 100 + day` in the lunar calendar: [name, isMajor]. */
const LUNAR = new Map([
  [101, ['春节', true]],
  [115, ['元宵节', true]],
  [202, ['龙抬头', false]],
  [303, ['上巳节', false]],
  [505, ['端午节', true]],
  [707, ['七夕节', false]],
  [715, ['中元节', false]],
  [815, ['中秋节', true]],
  [909, ['重阳节', false]],
  [1008, ['寒衣节', false]],
  [1208, ['腊八节', false]],
  [1223, ['北方小年', false]],
  [1224, ['南方小年', false]],
]);

/** Keyed by `month * 100 + day` in the Gregorian calendar: [name, isMajor]. */
const GREGORIAN = new Map([
  [101, ['元旦', true]],
  [214, ['情人节', false]],
  [308, ['妇女节', false]],
  [312, ['植树节', false]],
  [401, ['愚人节', false]],
  [501, ['劳动节', true]],
  [504, ['青年节', false]],
  [601, ['儿童节', false]],
  [701, ['建党节', false]],
  [801, ['建军节', false]],
  [910, ['教师节', false]],
  [1001, ['国庆节', true]],
  [1031, ['万圣夜', false]],
  [1224, ['平安夜', false]],
  [1225, ['圣诞节', false]],
]);

/** Nth weekday of a month; weekday 0 is Sunday. */
const FLOATING = [
  { month: 5, weekday: 0, ordinal: 2, name: '母亲节' },
  { month: 6, weekday: 0, ordinal: 3, name: '父亲节' },
  { month: 11, weekday: 4, ordinal: 4, name: '感恩节' },
];

/** Every festival on a calendar day, as `{ name, isMajor }`, most important first. */
export function festivalsOn(dn) {
  const found = [];
  const lunar = lunarDate(dn);

  if (isNewYearsEve(dn)) found.push({ name: '除夕', isMajor: true });
  if (!lunar.isLeapMonth) {
    const entry = LUNAR.get(lunar.month * 100 + lunar.day);
    if (entry) found.push({ name: entry[0], isMajor: entry[1] });
  }

  const p = parts(dn);
  const entry = GREGORIAN.get(p.month * 100 + p.day);
  if (entry) found.push({ name: entry[0], isMajor: entry[1] });

  const ordinal = Math.ceil(p.day / 7);
  for (const rule of FLOATING) {
    if (rule.month === p.month && rule.weekday === p.weekday && rule.ordinal === ordinal) {
      found.push({ name: rule.name, isMajor: false });
    }
  }

  // Stable sort: major festivals first, otherwise in the order found.
  return found.sort((a, b) => Number(b.isMajor) - Number(a.isMajor));
}
