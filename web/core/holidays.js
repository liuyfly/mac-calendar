// China's statutory holidays (放假) and make-up working days (调休补班).
// A port of HolidayStore.swift and HolidayFeedSource.swift.
//
// The State Council publishes each year's arrangement around November of the
// preceding year, so the bundled table always goes stale. Lookups fall back
// through: downloaded cache → bundled file → no data (cells simply show no
// badge, rather than guessing).

import { isoKey } from './days.js';

// MARK: - Sources

/** `{ "year": 2026, "papers": [...], "days": [{ date, isOffDay, name }] }` */
function parseHolidayCN(json, year) {
  if (!json || json.year !== year || !Array.isArray(json.days) || json.days.length === 0) {
    return null;
  }
  return json.days.map(({ date, isOffDay, name }) => ({ date, isOffDay, name }));
}

/**
 * `{ "holidays": { "2026-01-01": "New Year's Day,元旦,1" }, "workdays": {…} }`
 *
 * The payload carries no year of its own, so the requested year is used to
 * reject a file that answered with the wrong dates. `inLieuDays` is ignored:
 * those dates already appear in `holidays`.
 */
function parseChineseDays(json, year) {
  if (!json || typeof json.holidays !== 'object' || typeof json.workdays !== 'object') {
    return null;
  }
  const prefix = String(year);
  const chineseName = (label) => {
    const fields = String(label).split(',');
    return fields.length >= 2 ? fields[1] : String(label);
  };
  const days = [];
  for (const [date, label] of Object.entries(json.holidays ?? {})) {
    if (date.startsWith(prefix)) days.push({ date, isOffDay: true, name: chineseName(label) });
  }
  for (const [date, label] of Object.entries(json.workdays ?? {})) {
    if (date.startsWith(prefix)) days.push({ date, isOffDay: false, name: chineseName(label) });
  }
  if (days.length === 0) return null;
  return days.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
}

/**
 * Ordered by preference. holiday-cn is updated by CI straight from the State
 * Council announcements and publishes a year ahead; it is listed twice, on
 * two CDNs, because jsDelivr has been unreachable from mainland China before.
 */
export const SOURCES = [
  {
    name: 'holiday-cn (jsDelivr)',
    url: (year) => `https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/${year}.json`,
    parse: parseHolidayCN,
  },
  {
    name: 'holiday-cn (raw.githubusercontent)',
    url: (year) => `https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/${year}.json`,
    parse: parseHolidayCN,
  },
  {
    name: 'chinese-days',
    url: (year) => `https://cdn.jsdelivr.net/npm/chinese-days/dist/years/${year}.json`,
    parse: parseChineseDays,
  },
];

// MARK: - Store

const CACHE_PREFIX = 'holidays.';
const UPDATED_AT_KEY = 'holidays.updatedAt';
/** The arrangement changes once a year; a launch check is skipped if one succeeded recently. */
const REFRESH_INTERVAL_MS = 12 * 3600 * 1000;

export class HolidayStore {
  /**
   * @param storage a `localStorage`-like object for the downloaded years, or
   *   null to keep nothing between launches.
   */
  constructor(storage = null) {
    this.storage = storage;
    /** `year -> Map("yyyy-MM-dd" -> { isOffDay, name })` */
    this.table = new Map();
  }

  /** Loads the bundled `holidays.json`, which holds every year in one document. */
  loadBundled(json) {
    for (const [year, entry] of Object.entries(json?.years ?? {})) {
      this.merge(Number(year), entry.days ?? []);
    }
  }

  /** Loads years downloaded on earlier launches; they override the bundled ones. */
  loadCached() {
    if (!this.storage) return;
    for (let i = 0; i < this.storage.length; i++) {
      const key = this.storage.key(i);
      if (!key?.startsWith(CACHE_PREFIX) || key === UPDATED_AT_KEY) continue;
      try {
        const cached = JSON.parse(this.storage.getItem(key));
        this.merge(cached.year, cached.days);
      } catch {
        // A corrupt entry is ignored; the next refresh rewrites it.
      }
    }
  }

  merge(year, days) {
    if (!Number.isInteger(year) || !Array.isArray(days) || days.length === 0) return;
    this.table.set(year, new Map(days.map((d) => [d.date, { isOffDay: d.isOffDay, name: d.name }])));
  }

  /** `{ isOffDay, name }` for a calendar day, or null. */
  status(dn) {
    const key = isoKey(dn);
    return this.table.get(Number(key.slice(0, 4)))?.get(key) ?? null;
  }

  get availableYears() {
    return [...this.table.keys()].sort((a, b) => a - b);
  }

  get updatedAt() {
    const raw = this.storage?.getItem(UPDATED_AT_KEY);
    return raw ? new Date(Number(raw)) : null;
  }

  /**
   * Fetches the current and next year. Each year tries the sources in order
   * and stops at the first that answers. Failures are silent by design: the
   * calendar stays usable on the bundled data.
   *
   * Resolves to the years that were updated.
   */
  async refresh({ force = false, now = new Date(), fetchImpl = globalThis.fetch } = {}) {
    const last = this.updatedAt;
    if (!force && last && now - last < REFRESH_INTERVAL_MS) return [];

    const year = now.getFullYear();
    const results = await Promise.all([year, year + 1].map(async (y) => {
      for (const source of SOURCES) {
        try {
          const response = await fetchImpl(source.url(y), { cache: 'no-store' });
          // A 404 for a year not published yet, a CDN error page, a schema
          // change — anything unusable moves on to the next source.
          if (!response.ok) continue;
          const days = source.parse(await response.json(), y);
          if (!days) continue;
          this.merge(y, days);
          this.write(y, days, source.name);
          return y;
        } catch {
          continue;
        }
      }
      return null;
    }));

    const updated = results.filter((y) => y !== null);
    if (updated.length > 0) this.storage?.setItem(UPDATED_AT_KEY, String(now.getTime()));
    return updated;
  }

  write(year, days, source) {
    try {
      this.storage?.setItem(CACHE_PREFIX + year, JSON.stringify({ year, source, days }));
    } catch {
      // Storage full or unavailable: the data still applies for this session.
    }
  }

  /** "已覆盖 2025、2026 年 · 上次更新 9月24日", shown in settings. */
  coverageSummary() {
    const years = this.availableYears;
    const yearText = years.length === 0 ? '无数据' : `已覆盖 ${years.join('、')} 年`;
    const at = this.updatedAt;
    if (!at) return yearText;
    return `${yearText} · 上次更新 ${at.getMonth() + 1}月${at.getDate()}日`;
  }

  /** What to tell the user after a manual refresh. */
  static refreshResultMessage(years) {
    return years.length === 0 ? '更新失败，继续使用现有数据' : `已更新 ${years.join('、')} 年`;
  }
}
