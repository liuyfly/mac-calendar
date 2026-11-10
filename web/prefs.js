// User settings, kept in localStorage. Losing them only means the defaults
// come back, so every access tolerates storage being unavailable.

const KEY = 'prefs';

const DEFAULTS = Object.freeze({
  /** 'system' | 'light' | 'dark' */
  appearance: 'system',
  weekStartsOnMonday: true,
  showSolarTerms: true,
  showHolidayBadges: true,
});

/** localStorage, or null where it throws (private mode, blocked storage). */
export const storage = (() => {
  try {
    const s = globalThis.localStorage;
    const probe = '__probe__';
    s.setItem(probe, probe);
    s.removeItem(probe);
    return s;
  } catch {
    return null;
  }
})();

export function loadPrefs() {
  try {
    const saved = JSON.parse(storage?.getItem(KEY) ?? '{}');
    const prefs = { ...DEFAULTS };
    for (const key of Object.keys(DEFAULTS)) {
      if (typeof saved[key] === typeof DEFAULTS[key]) prefs[key] = saved[key];
    }
    return prefs;
  } catch {
    return { ...DEFAULTS };
  }
}

export function savePrefs(prefs) {
  try {
    storage?.setItem(KEY, JSON.stringify(prefs));
  } catch {
    // Not persisted; still applies until the app is closed.
  }
}
