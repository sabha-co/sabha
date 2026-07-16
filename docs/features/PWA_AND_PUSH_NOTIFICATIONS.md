# PWA & Push Notifications

Sabha's Progressive Web App and push notification architecture.

## Architecture Overview

### Push Notification Flow

```
Subscribe:  notifications_controller.js -> PushManager.subscribe(VAPID) -> POST /user_push_subscriptions
Trigger:    Message after_create_commit -> Notification::DispatchJob
Route:      Message#notify_recipients -> deliver_push_for(activity_type)
            (activity_type is one of :mention, :direct_message, :everyone_room_message, :thread_reply)
Recipients: Message#push_recipient_user_ids_for + Membership::Notifiable#receives_push_for?
Build:      Room::MessagePusher.payload_for builds the payload (title, body, path, badge count)
Queue:      WebPush::Pool#queue (one job per (subscription, payload) pair)
Deliver:    50-thread executor -> WebPush::Notification -> Net::HTTP::Persistent -> push service
Display:    Service worker push event -> showNotification() + setAppBadge()
Click:      notificationclick -> navigate to room path (focus existing or open new window)
```

Routing decisions (who is eligible for which channel) are the broader notification system's responsibility — see [NOTIFICATIONS.md](NOTIFICATIONS.md). This doc covers the PWA shell and the push transport only.

### Key Files

| Purpose | Path |
|---------|------|
| VAPID config | `config/initializers/vapid.rb` |
| Pool + persistent-HTTP monkey-patch | `config/initializers/web_push.rb`, `lib/web_push/pool.rb` |
| SSRF protection (allowlist + IP pin) | `app/models/ssrf_protection.rb`, `app/models/push/subscription.rb` |
| Subscription model | `app/models/push/subscription.rb` |
| Subscription controller | `app/controllers/users/push_subscriptions_controller.rb` |
| Routing vocabulary | `app/models/notification/routing.rb` (`PUSH_TYPES`) |
| Recipient resolution | `app/models/message.rb` (`push_recipient_user_ids_for`, `deliver_push_for`) |
| Per-recipient eligibility | `app/models/membership/notifiable.rb` (`receives_push_for?`, `common_gates_pass?`) |
| Payload builder | `app/models/room/message_pusher.rb` |
| Notification payload (transport) | `lib/web_push/notification.rb` |
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

### Notification Filtering

Push routing follows `Notification::Routing::PUSH_TYPES`, which currently fires for four activity types: `:mention`, `:direct_message`, `:everyone_room_message`, and `:thread_reply`. For each message, `Message#notify_recipients` resolves the recipient set per type and asks `Membership::Notifiable#receives_push_for?(activity_type)` for each candidate.

A membership receives a push only when **all** of the following hold (`receives_push_for?` + `common_gates_pass?`):

- The user has `push_enabled` and is not banned/deactivated.
- The membership's `effective_involvement` (per-room value layered over the user's global mode) matches the activity type — e.g. `:mention` requires at least `:mentions`, room messages require `:everything`.
- The user is **not currently watching** that room — read live from the anycable-go broker (`Room::PresenceSet`), falling back to `Membership::Connectable#connected?` (5-minute TTL on `connected_at`) only when the broker can't answer.
- The user is not the message author and is not blocked by the author (or vice versa — block is symmetric for `can_ping?`).
- The user has at least one valid `Push::Subscription` row.

Direct messages, `@everyone` broadcasts, and thread replies have type-specific recipient resolution but share the same per-recipient gates. See [NOTIFICATIONS.md](NOTIFICATIONS.md#5-routing-dispatcher) for the full dispatcher.

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

- **Delivery pool:** 50 max threads, 10,000 queue size.
- **Invalidation pool:** 1 thread (serial cleanup of expired subscriptions).
- **Persistent HTTP:** `Net::HTTP::Persistent` with a 150-conn pool. The `WebPush` gem doesn't use it natively, so `config/initializers/web_push.rb` monkey-patches a `WebPush::PersistentRequest` adapter onto the gem.
- **Error handling:** `WebPush::ExpiredSubscription` (HTTP 404/410) and `OpenSSL::OpenSSLError` trigger auto-destroy of the offending subscription on the invalidation pool.
- **SaaS support:** captures and restores `ApplicationRecord.current_tenant` across thread boundaries so deliveries run with the correct tenant DB connection.
- **SSRF protection:** `Push::Subscription` validates the endpoint URL against an HTTPS-only allowlist (`PERMITTED_ENDPOINT_HOSTS`) at create time and pins the resolved IP (`resolved_endpoint_ip`) so a later DNS swap can't redirect a delivery to an internal host.

## Design Decisions

- **Presence-aware delivery**: push gating asks the anycable-go broker who is watching the room (`Room::PresenceSet`), so members actively viewing a room don't receive push notifications. The membership connection columns survive as the fallback signal (5-minute TTL) for when the broker is unreachable.
- **Room-type payloads**: Notification payloads are built based on room type (direct, shared, thread) rather than event type, keeping the payload logic simple.
- **PWA install prompt**: `pwa_install_controller.js` intercepts `beforeinstallprompt` with platform-specific install instructions rather than relying on native browser prompts.
- **Dynamic VAPID subject**: Uses `"mailto:#{Branding.support_email}"` so push service contact info matches your deployment.

## iOS Safari

Web push on iOS requires the site to be installed as a PWA — the user must add Sabha to the home screen first, then grant notification permission from within the installed app. Safari in the standard browser tab cannot subscribe. `pwa_install_controller.js` surfaces the "Add to Home Screen" instructions for iOS users who tap the enable-notifications affordance before installing.
