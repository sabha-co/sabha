# PWA & Push Notifications

Review of Sabha's implementation compared with Fizzy. Both share the same core infrastructure.

## Architecture Overview

### Push Notification Flow

```
Subscribe: notifications_controller.js -> PushManager.subscribe(VAPID) -> POST /user_push_subscriptions
Trigger:   Message created -> room.receive -> Room::PushMessageJob (Solid Queue)
Build:     Room::MessagePusher builds payload (title, body, path, badge count)
Filter:    Only disconnected users (60s TTL) with "everything" or "mentions" involvement
Deliver:   WebPush::Pool (50-thread pool) -> encrypted VAPID payload -> push service
Display:   Service worker push event -> showNotification() + setAppBadge()
Click:     notificationclick -> navigate to room path (focus existing or open new window)
```

### Key Files

| Purpose | Path |
|---------|------|
| VAPID config | `config/initializers/vapid.rb` |
| Pool + error handling | `config/initializers/web_push.rb`, `lib/web_push/pool.rb` |
| SSRF protection | `app/models/ssrf_protection.rb` |
| Subscription model | `app/models/push/subscription.rb` |
| Subscription controller | `app/controllers/users/push_subscriptions_controller.rb` |
| Who gets notified | `app/models/room/message_pusher.rb` |
| Job | `app/jobs/room/push_message_job.rb` |
| Notification payload | `lib/web_push/notification.rb` |
| Frontend subscription | `app/javascript/controllers/notifications_controller.js` |
| Service worker | `app/views/pwa/service_worker.js` |
| Manifest | `app/views/pwa/manifest.json.erb` |
| PWA controller | `app/controllers/pwa_controller.rb` |
| PWA install prompt | `app/javascript/controllers/pwa_install_controller.js` |

### PWA Features

- **Web App Manifest** — dynamic manifest at `/webmanifest` with branding, icons (192/512px maskable), shortcuts
- **Service Worker** — push notifications + network-first offline fallback for document requests
- **Install Prompt** — Stimulus controller intercepts `beforeinstallprompt`, defers it, provides platform-specific instructions
- **Badge API** — unread room count on app icon via `setAppBadge()`/`clearAppBadge()`
- **CSS helpers** — `.hide-in-pwa`, `.hide-in-browser`, `.hide-in-ios-pwa` via `display-mode: standalone` media queries

### VAPID

VAPID (Voluntary Application Server Identification for Web Push) lets the server prove its identity to push services (FCM, APNs, Mozilla Push) without per-service API keys.

- Key pair loaded from env vars or Rails credentials (`config/initializers/vapid.rb`)
- Public key exposed via `<meta name="vapid-public-key">` in layout
- Private key signs each push delivery in `WebPush::Notification`
- Subject set to `"mailto:#{Branding.support_email}"` (dynamic)

### Notification Filtering (MessagePusher)

Two paths for determining recipients:

1. **Users with `involvement: "everything"`** — all messages in the room
2. **Users with `involvement: "mentions"`** — only when @mentioned (`@user`, `@everyone`, quoted authors)

Both paths additionally filter by:
- `Membership.visible` (not invisible)
- `Membership.disconnected` (not currently connected — 60 sec TTL on `connected_at`)
- Not the message creator

### Payload Structure

Direct messages:
```ruby
{ title: creator.name, body: message_text, path: room_path }
```

Shared rooms (open/closed):
```ruby
{ title: room.display_name, body: "#{creator.name}: #{message_text}", path: room_path }
```

Threads: include link to parent message.

Badge count (unread rooms) included in all payloads.

### Delivery Infrastructure (WebPush::Pool)

- **Delivery pool:** 50 max threads, 10,000 queue size
- **Invalidation pool:** 1 thread (serial cleanup of expired subscriptions)
- **Persistent HTTP:** `Net::HTTP::Persistent` reuses connections
- **Error handling:** `WebPush::ExpiredSubscription` and `OpenSSL::OpenSSLError` trigger auto-destroy of subscription
- **SaaS support:** captures and restores tenant context across thread boundaries

## Comparison with Fizzy

### Shared Infrastructure

Both apps use identical patterns for:
- `WebPush::Pool` (50 threads, 10K queue, persistent HTTP)
- `WebPush::Notification` (same payload structure, endpoint IP pinning)
- `Push::Subscription` model (SSRF-validated endpoints, permitted host allowlist, IP pinning)
- `SsrfProtection` module (public DNS resolution, private/loopback/link-local/CGNAT rejection)
- Service worker (fetch offline fallback + push + badge + notificationclick)
- VAPID initializer
- Stimulus `notifications_controller.js`
- `discard_on ActiveJob::DeserializationError` on push jobs

### Differences

#### Notification Trigger

| | Sabha | Fizzy |
|---|---|---|
| Trigger | `Room#receive` -> `Room::PushMessageJob` | `Notification#after_create_commit` -> `PushNotificationJob` |
| Pusher | `Room::MessagePusher` (room-scoped) | `NotificationPusher` (notification-scoped) |
| Filtering | Membership involvement level + connection state | `user.push_subscriptions.any?`, `!creator.system?`, `user.active?`, `account.active?` |

Sabha filters at the room membership level. Fizzy filters at the notification model level.

#### Connection-Aware Delivery — Sabha only

Sabha tracks `connected_at` on memberships with a 60-second TTL. Users actively viewing a room don't get push. Fizzy sends push to all subscribed users regardless.

#### Notification Payloads

Sabha builds payloads based on **room type** (direct, shared, thread). Fizzy builds payloads based on **event type** (comment_created, card_assigned, card_published, mention, etc.).

#### PWA Install Prompt — Sabha only

Sabha has `pwa_install_controller.js` that intercepts `beforeinstallprompt` with platform-specific install instructions. Fizzy relies on native browser prompts.

#### Subscription Deduplication

| | Sabha | Fizzy |
|---|---|---|
| Unique index | `(endpoint, p256dh_key, auth_key)` | `(user_id, endpoint)` |
| Create strategy | `find_or_create_by` + touch | `create_or_find_by!` |

#### VAPID Subject

- Sabha: `"mailto:#{Branding.support_email}"` (dynamic)
- Fizzy: `"mailto:support@fizzy.do"` (hardcoded)

### What Fizzy Could Adopt from Sabha

1. **Connection-aware delivery** — skip push for users actively viewing the app
2. **PWA install prompt** handling with platform-specific instructions
3. **Dynamic VAPID subject** instead of hardcoded email
