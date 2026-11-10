// Keeps the app working offline. Every file is cached under the build's
// version; a new build changes this file, which installs a fresh cache and
// drops the old one. The app is small and changes rarely, so it is served
// cache-first: a new version shows on the launch after it is downloaded.

const VERSION = '__VERSION__';
const CACHE = `lunar-calendar-${VERSION}`;

const FILES = [
  './',
  'index.html',
  'app.css',
  'app.js',
  'prefs.js',
  'version.js',
  'core/calendar.js',
  'core/days.js',
  'core/festivals.js',
  'core/holidays.js',
  'core/lunar.js',
  'core/lunar-table.js',
  'core/solar-terms.js',
  'core/vsop87.js',
  'holidays.json',
  'manifest.webmanifest',
  'icons/apple-touch-icon.png',
  'icons/icon-192.png',
  'icons/icon-512.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // Bypass the HTTP cache so a new version never caches old files.
    await cache.addAll(FILES.map((url) => new Request(url, { cache: 'reload' })));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key !== CACHE) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  // Holiday feeds and anything else off-site go straight to the network.
  if (request.method !== 'GET' || new URL(request.url).origin !== self.location.origin) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const lookup = request.mode === 'navigate' ? './' : request;
    const cached = await cache.match(lookup, { ignoreSearch: true });
    return cached ?? fetch(request);
  })());
});
