// Admin dashboard service worker. Registered with scope /admin from admin/shared/_head. It also
// receives web push for the dashboard (admin_push.js registers the token).
//
// Deliberately network-only for pages: every admin page is behind a session and shows
// live data (pending reviews, subscriptions), so caching it would serve stale numbers and
// leave one admin's pages on a shared device after logout. The only thing cached is a
// static offline page, shown when a navigation fails because there is no network.
// Bump VERSION when offline.html or its assets change.
const VERSION = "v1";
const CACHE = `admin-offline-${VERSION}`;
const OFFLINE_URL = "/offline.html";
const PRECACHE = [ OFFLINE_URL, "/brand/web/mark.png" ];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(PRECACHE)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

// Web push (FCM). The message arrives as FCM's JSON: { notification: { title, body }, data }.
// Always show something: a push the page does not display counts against the site in Chrome.
self.addEventListener("push", (event) => {
  let message = {};
  try {
    message = event.data ? event.data.json() : {};
  } catch (_error) {
    // not JSON: fall through to the generic notification
  }
  const notification = message.notification || {};
  const data = message.data || {};

  event.waitUntil(
    self.registration.showNotification(notification.title || "أجهور الكبرى", {
      body: notification.body || "",
      icon: "/brand/web/icon-192.png",
      lang: "ar",
      dir: "rtl",
      data,
      // FCM delivers at least once; the same notification replaces itself instead of stacking.
      tag: data.notification_id ? `notification-${data.notification_id}` : undefined
    })
  );
});

// Opens the page the server chose (PushNotificationJob adds admin_path for web devices). Only
// dashboard paths are followed, so a payload can never send the admin to another site.
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const path = (event.notification.data || {}).admin_path;
  const target = typeof path === "string" && /^\/admin(\/|$)/.test(path) ? path : "/admin";
  event.waitUntil(self.clients.openWindow(target));
});

self.addEventListener("fetch", (event) => {
  // Only page navigations; assets, forms and the search endpoint go straight to the network.
  if (event.request.mode !== "navigate") return;

  event.respondWith(
    fetch(event.request).catch(() => caches.match(OFFLINE_URL))
  );
});
