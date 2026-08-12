const OFFLINE_CACHE = 'sabha-offline-v1'
const OFFLINE_URL = '/offline.html'

// Precache the self-contained offline shell so a failed navigation has
// something to fall back to. It inlines its own styles, so it renders without
// any other cached asset.
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(OFFLINE_CACHE).then((cache) => cache.add(new Request(OFFLINE_URL, { cache: 'reload' })))
  )
  self.skipWaiting()
})

// Drop caches from earlier worker versions so the shell can't go stale.
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((key) => key !== OFFLINE_CACHE).map((key) => caches.delete(key)))
    ).then(() => self.clients.claim())
  )
})

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return

  if (event.request.destination === 'document') {
    event.respondWith(
      fetch(event.request, { cache: 'no-cache' })
        .catch(() => caches.match(OFFLINE_URL))
    )
  }
})

self.addEventListener("push", (event) => {
  const data = event.data.json()
  event.waitUntil(Promise.all([ showNotification(data), updateBadgeCount(data.options) ]))
})

async function showNotification({ title, options }) {
  return self.registration.showNotification(title, options)
}

async function updateBadgeCount({ data: { badge } }) {
  return self.navigator.setAppBadge?.(badge || 0)
}

self.addEventListener("notificationclick", (event) => {
  event.notification.close()

  const url = new URL(event.notification.data.path, self.location.origin).href
  event.waitUntil(openURL(url))
})

async function openURL(url) {
  const clients = await self.clients.matchAll({ type: "window" })
  const focused = clients.find((client) => client.focused)

  if (focused) {
    await focused.navigate(url)
  } else {
    await self.clients.openWindow(url)
  }
}
