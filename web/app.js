// The app's only screen: month header, the paged grid, the details of the
// focused day, and the settings sheet. Mirrors iOS/App/CalendarScreen.swift.

import { today, parts, addMonths, dayNumber, msUntilMidnight } from './core/days.js';
import { makeMonth, focusedDay, footerTitle, footerDetail, detailLine } from './core/calendar.js';
import { HolidayStore } from './core/holidays.js';
import { loadPrefs, savePrefs, storage } from './prefs.js';
import { VERSION } from './version.js';

const $ = (id) => document.getElementById(id);

const prefs = loadPrefs();
const holidays = new HolidayStore(storage);

const now = parts(today());
const state = {
  year: now.year,
  month: now.month,
  /** Day number of the selected day, or null. */
  selected: null,
  today: today(),
};

const el = {
  title: $('month-title'),
  subtitle: $('month-subtitle'),
  weekdays: $('weekdays'),
  pages: $('pages'),
  track: $('track'),
  footerTitle: $('footer-title'),
  footerDetail: $('footer-detail'),
};

// The three pages: previous, current and next month.
const pageEls = ['previous', 'current', 'next'].map((name) => {
  const page = document.createElement('div');
  page.className = `page ${name}`;
  if (name !== 'current') page.setAttribute('aria-hidden', 'true');
  el.track.append(page);
  return page;
});

// MARK: - Rendering

function monthModel(year, month) {
  return makeMonth(year, month, { today: state.today, prefs, holidays });
}

function escapeText(text) {
  return text.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

function cellHTML(d) {
  const classes = ['cell'];
  if (!d.inMonth) classes.push('other');
  if (d.isToday) classes.push('today');
  else if (d.dn === state.selected) classes.push('selected');
  // A traded-away weekend is a working day; the weekend colour would say the
  // opposite of the 班 badge next to it.
  if (d.holiday ? d.holiday.isOffDay : d.isWeekend) classes.push('red');

  const sub = d.subtitle;
  const subClasses = ['sub', sub.kind];
  if (sub.text.length >= 4) subClasses.push('long');
  const badge = d.holiday
    ? `<span class="badge ${d.holiday.isOffDay ? 'off' : 'work'}">${d.holiday.isOffDay ? '休' : '班'}</span>`
    : '';
  const label = `${d.day}日 ${detailLine(d)}${d.holiday ? (d.holiday.isOffDay ? ' 休' : ' 班') : ''}`;
  return `<button type="button" class="${classes.join(' ')}" data-dn="${d.dn}" aria-label="${escapeText(label)}">`
    + `<span class="num">${d.day}</span><span class="${subClasses.join(' ')}">${escapeText(sub.text)}</span>${badge}</button>`;
}

function renderPage(page, model) {
  page.innerHTML = model.days.map(cellHTML).join('');
}

/** Rebuilds everything for the current state. */
function render() {
  const current = monthModel(state.year, state.month);
  const prev = addMonths(state.year, state.month, -1);
  const next = addMonths(state.year, state.month, 1);
  renderPage(pageEls[0], monthModel(prev.year, prev.month));
  renderPage(pageEls[1], current);
  renderPage(pageEls[2], monthModel(next.year, next.month));

  el.title.textContent = `${current.year}年 ${current.month}月`;
  el.subtitle.textContent = `${current.yearSummary} · ${current.lunarMonthSummary}`;
  el.weekdays.innerHTML = current.weekdaySymbols
    .map((s, i) => `<span${current.weekendColumns.includes(i) ? ' class="weekend"' : ''}>${s}</span>`)
    .join('');

  const focused = focusedDay(current, state.selected);
  el.footerTitle.textContent = footerTitle(focused);
  el.footerDetail.textContent = footerDetail(focused);
}

// MARK: - Paging

let offset = 0;
/** True while a page is settling onto a new month. */
let paging = false;
/** Arrow taps that arrived while a page was settling, run in turn after it. */
let queuedSteps = 0;

const pageWidth = () => el.pages.clientWidth;

function setOffset(x, duration = 0) {
  el.track.style.transition = duration ? `transform ${duration}ms cubic-bezier(0.25, 0.8, 0.3, 1)` : 'none';
  el.track.style.transform = x ? `translate3d(${x}px, 0, 0)` : '';
  offset = x;
}

/**
 * Slides the pages to `target`, then commits the move. Once a page settles,
 * the state moves to that month and the offset snaps back to zero in the
 * same frame: the page now in the middle shows exactly what the neighbour
 * showed, so nothing visibly changes.
 *
 * @param velocity the finger's speed in px/s, so a flick hands off smoothly.
 */
function settle(target, velocity, commit) {
  paging = Boolean(commit);
  const distance = Math.abs(target - offset);
  const finish = () => {
    if (commit) {
      commit();
      setOffset(0);
      render();
      // Flush the snap-back before any new transition starts.
      void el.track.offsetWidth;
    }
    paging = false;
    if (queuedSteps !== 0) {
      const direction = Math.sign(queuedSteps);
      queuedSteps -= direction;
      step(direction);
    }
  };
  if (distance < 1 || reducedMotion.matches) {
    setOffset(target);
    finish();
    return;
  }
  // The ease-out curve starts at roughly twice its average speed, so match
  // that to the finger; a slow drag or a button press gets the full duration.
  const speed = Math.abs(velocity);
  const duration = speed > 0 ? Math.max(180, Math.min(380, (distance / speed) * 1000 * 2)) : 380;
  setOffset(target, duration);

  let done = false;
  const once = () => {
    if (done) return;
    done = true;
    el.track.removeEventListener('transitionend', once);
    finish();
  };
  el.track.addEventListener('transitionend', once);
  setTimeout(once, duration + 80);   // transitionend can be skipped, e.g. in the background
}

const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');

function moveMonth(delta) {
  const m = addMonths(state.year, state.month, delta);
  state.year = m.year;
  state.month = m.month;
}

function step(delta) {
  if (paging) {
    queuedSteps += delta;
    return;
  }
  settle(-delta * pageWidth(), 0, () => moveMonth(delta));
}

/**
 * Slides to today's month. Several months away, the neighbour on that side
 * is redrawn as today's month first, so the page that slides in is the one
 * that stays.
 */
function goToToday() {
  queuedSteps = 0;
  if (paging) return;
  state.today = today();
  const t = parts(state.today);
  const target = t.year * 12 + t.month - 1;
  const current = state.year * 12 + state.month - 1;
  const direction = Math.sign(target - current);
  const commit = () => {
    state.year = t.year;
    state.month = t.month;
    state.selected = null;
  };
  if (direction === 0) {
    commit();
    render();
    return;
  }
  if (Math.abs(target - current) > 1) {
    renderPage(pageEls[direction > 0 ? 2 : 0], monthModel(t.year, t.month));
  }
  settle(-direction * pageWidth(), 0, commit);
}

/** A tap on a day borrowed from a neighbouring month pages to that month. */
function select(dn) {
  if (paging) return;
  const p = parts(dn);
  if (p.year === state.year && p.month === state.month) {
    state.selected = state.selected === dn ? null : dn;
    render();
    return;
  }
  const direction = dn < dayNumber(state.year, state.month, 1) ? -1 : 1;
  settle(-direction * pageWidth(), 0, () => {
    state.year = p.year;
    state.month = p.month;
    state.selected = dn;
  });
}

// MARK: - Gestures

/** The drag in progress, if any. */
let gesture = null;
/** Set after a drag so the click that ends it is not taken as a tap. */
let suppressClick = false;

el.pages.addEventListener('pointerdown', (e) => {
  if (paging || !e.isPrimary || e.button !== 0) return;
  gesture = { id: e.pointerId, x0: e.clientX, y0: e.clientY, decided: false, horizontal: false, samples: [] };
});

el.pages.addEventListener('pointermove', (e) => {
  if (!gesture || e.pointerId !== gesture.id) return;
  const dx = e.clientX - gesture.x0;
  const dy = e.clientY - gesture.y0;
  if (!gesture.decided) {
    if (Math.hypot(dx, dy) < 10) return;
    // Decided once, at the start: a mostly vertical drag is left alone.
    gesture.decided = true;
    gesture.horizontal = Math.abs(dx) > Math.abs(dy);
    if (gesture.horizontal) el.pages.setPointerCapture(e.pointerId);
  }
  if (!gesture.horizontal) return;
  setOffset(dx);
  const t = e.timeStamp;
  gesture.samples.push({ x: e.clientX, t });
  while (gesture.samples.length > 2 && t - gesture.samples[0].t > 100) gesture.samples.shift();
});

function endGesture(e, cancelled) {
  if (!gesture || e.pointerId !== gesture.id) return;
  const g = gesture;
  gesture = null;
  if (!g.horizontal) return;
  suppressClick = true;
  setTimeout(() => { suppressClick = false; }, 0);

  const dx = e.clientX - g.x0;
  const first = g.samples[0];
  const last = g.samples[g.samples.length - 1];
  const velocity = first && last && last.t > first.t ? ((last.x - first.x) / (last.t - first.t)) * 1000 : 0;

  // A flick counts even if it did not travel far; a slow drag needs to pass
  // a third of the page.
  let direction = 0;
  if (!cancelled) {
    if (Math.abs(velocity) > 300) direction = velocity < 0 ? 1 : -1;
    else if (Math.abs(dx) > pageWidth() / 3) direction = dx < 0 ? 1 : -1;
  }
  if (direction === 0) settle(0, velocity, null);
  else settle(-direction * pageWidth(), velocity, () => moveMonth(direction));
}

el.pages.addEventListener('pointerup', (e) => endGesture(e, false));
el.pages.addEventListener('pointercancel', (e) => endGesture(e, true));

el.pages.addEventListener('click', (e) => {
  if (suppressClick) return;
  const cell = e.target.closest('.page.current .cell');
  if (cell) select(Number(cell.dataset.dn));
});

$('prev').addEventListener('click', () => step(-1));
$('next').addEventListener('click', () => step(1));
$('today').addEventListener('click', goToToday);

// MARK: - Appearance

const themeMetas = [...document.querySelectorAll('meta[name="theme-color"]')];
const themeColors = { light: '#ffffff', dark: '#000000' };

function applyAppearance() {
  const root = document.documentElement;
  if (prefs.appearance === 'system') {
    delete root.dataset.theme;
    themeMetas.forEach((m) => { m.content = themeColors[m.media.includes('dark') ? 'dark' : 'light']; });
  } else {
    root.dataset.theme = prefs.appearance;
    themeMetas.forEach((m) => { m.content = themeColors[prefs.appearance]; });
  }
}

// MARK: - Settings

const settings = $('settings');
const holidayStatus = $('holiday-status');
const refreshButton = $('refresh-holidays');

function syncSettingsControls() {
  for (const group of settings.querySelectorAll('.segmented')) {
    const value = String(prefs[group.dataset.pref]);
    for (const button of group.querySelectorAll('button')) {
      button.setAttribute('aria-pressed', String(button.dataset.value === value));
    }
  }
  for (const input of settings.querySelectorAll('input[data-pref]')) {
    input.checked = prefs[input.dataset.pref];
  }
}

function openSettings() {
  syncSettingsControls();
  holidayStatus.textContent = holidays.coverageSummary();
  settings.hidden = false;
  requestAnimationFrame(() => requestAnimationFrame(() => settings.classList.add('open')));
}

function closeSettings() {
  settings.classList.remove('open');
  const sheet = settings.querySelector('.sheet');
  let done = false;
  const hide = () => {
    if (done) return;
    done = true;
    settings.hidden = true;
  };
  sheet.addEventListener('transitionend', hide, { once: true });
  setTimeout(hide, 450);
}

/** Settings apply as they are changed, not when the sheet closes. */
function updatePref(key, value) {
  prefs[key] = value;
  savePrefs(prefs);
  syncSettingsControls();
  applyAppearance();
  render();
}

$('open-settings').addEventListener('click', openSettings);
settings.addEventListener('click', (e) => {
  if (e.target.closest('[data-close]')) closeSettings();
  const option = e.target.closest('.segmented button');
  if (option) {
    const key = option.parentElement.dataset.pref;
    const raw = option.dataset.value;
    updatePref(key, typeof prefs[key] === 'boolean' ? raw === 'true' : raw);
  }
});
settings.addEventListener('change', (e) => {
  if (e.target.matches('input[data-pref]')) updatePref(e.target.dataset.pref, e.target.checked);
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && !settings.hidden) closeSettings();
});

refreshButton.addEventListener('click', async () => {
  refreshButton.disabled = true;
  refreshButton.textContent = '正在更新…';
  const years = await holidays.refresh({ force: true });
  refreshButton.disabled = false;
  refreshButton.textContent = '检查更新';
  holidayStatus.textContent = HolidayStore.refreshResultMessage(years);
  if (years.length > 0) render();
});

$('version').textContent = VERSION;

const isStandalone = matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
$('install-hint').hidden = isStandalone;

// MARK: - Lifecycle

/** Set when the page is hidden, so the return can be told apart from a first load. */
let wasHidden = false;

/**
 * Returning to the app shows the current month, as the macOS panel does on
 * every opening, and picks up a date that rolled over in the background.
 */
document.addEventListener('visibilitychange', () => {
  if (document.hidden) {
    wasHidden = true;
    return;
  }
  if (!wasHidden) return;
  wasHidden = false;
  if (!settings.hidden) return;   // leave an open settings sheet alone
  queuedSteps = 0;
  if (!paging) {
    const t = parts(today());
    state.today = today();
    state.year = t.year;
    state.month = t.month;
    state.selected = null;
    render();
  }
  refreshHolidays();
});

function scheduleMidnight() {
  setTimeout(() => {
    state.today = today();
    if (!paging) render();
    scheduleMidnight();
  }, msUntilMidnight());
}

async function refreshHolidays() {
  const years = await holidays.refresh();
  if (years.length > 0 && !paging) render();
}

async function loadHolidays() {
  try {
    const response = await fetch('holidays.json');
    if (response.ok) holidays.loadBundled(await response.json());
  } catch {
    // No bundled data: cells show no badge rather than a guess.
  }
  holidays.loadCached();
  render();
  refreshHolidays();
}

// MARK: - Start

applyAppearance();
render();
loadHolidays();
scheduleMidnight();

if (VERSION !== 'dev' && 'serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(() => {
    // Without a service worker the app still works, just not offline.
  });
}
