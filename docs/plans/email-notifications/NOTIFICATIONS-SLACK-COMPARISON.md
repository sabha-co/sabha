# Planned notification changes compared to Slack

**Status:** Companion note for `NOTIFICATIONS-ARCHITECTURE.md`.
**Verified:** 2026-05-09.
**Purpose:** Make the Slack comparison explicit so the implementation plan does not quietly inherit Slack-shaped assumptions we are not actually shipping.

## Slack baseline

Slack's public help docs describe two different email surfaces:

- **Notification emails**: missed-activity emails sent when a user is not active in Slack. Slack says these can alert users about mentions, DMs, and replies to threads they follow. Slack bundles these emails and delivers them every 15 minutes or once an hour, depending on user preference.
- **Email news and updates**: product/news/tip/feedback emails. These are managed separately under "Email news and updates" and are not the same thing as missed-message notification email.

### What "not active in Slack" means

Slack does **not** define this precisely in its email-notification docs. The notification guide simply says *"When you're not active in Slack, you can receive email notifications…"* and links to its presence article for the definition. From that article:

- **Active**: Slack is open on a desktop or mobile client and Slack is detecting interaction.
- **Away** (set automatically): triggered by either *10 minutes of desktop cursor inactivity* or *navigating away from / closing the Slack app on mobile*. Users can also manually flip their status to active or away at any time.

Mobile push has its own tighter threshold ("one minute after locking your desktop screen or 10 minutes after Slack stops detecting cursor activity"). Email uses the broader presence rule above and then waits for the bundle window (15 min or 1 hour) to pass before sending.

Two practical implications:

1. Slack's "not active" signal is **presence-driven** — it tracks cursor activity and which clients are open. It is not a single "time since last connection" number.
2. There is no documented account-level *email feature flag* that admins flip on or off. Email is configured per user.

Sources:

- Slack notification guide: https://slack.com/help/articles/360025446073-Guide-to-Slack-notifications
- Slack notification configuration: https://slack.com/hc/en-us/articles/201649273-Configuring-email-notifications
- Slack presence and availability: https://slack.com/help/articles/201864558-Set-your-Slack-status-and-availability
- Slack email subscriptions: https://slack.com/intl/en-in/help/articles/360003868571-Manage-your-Slack-email-subscriptions

## Sabha v1 plan

Sabha v1 is Slack-inspired, not Slack-equivalent.

The planned v1 behavior:

- Email for `:mention`, `:direct_message`, and `@everyone` / room-wide mentions when the user would receive an in-app mention row.
- Email only when the user is **workspace-locally away** — last connection in this workspace's memberships is more than 1 hour ago (`Membership::Connectable::ACTIVITY_TIERS[:away]`).
- Existing and new users default to `missed_email_enabled: false`.
- Account/workspace email feature flag (`account.email_notifications_enabled`) defaults off.
- Missed-notification emails are bundled per user, with hourly or daily windows (user choice).
- Weekly activity digest is available when a workspace admin enables it; members default to `weekly_digest_subscribed: true` (admin-enabled, member opt-out — PRD § Product principles #6).
- **Snooze / DND is not a v1 feature, in any form.** No `snooze_until` column, no `snooze_indefinite` flag, no presence-as-snooze beyond the workspace-locally-away check. "User is unavailable" rides on passive presence and per-channel master switches.
- Thread-reply email is **deferred to v1.1+**, not part of v1. `:thread_reply` is intentionally absent from `Notification::Routing::EMAIL_TYPES` while we observe v1 bundle volume. Sabha already has the recipient set wired (thread members + parent room `involved_in_everything`, minus already-mentioned users), so the v1.1 path is mostly opting `:thread_reply` into `EMAIL_TYPES` and adding it to `notification_bundle_items.kind`.

## Comparison

| Area | Slack | Sabha v1 |
|---|---|---|
| Email trigger | Presence-driven: "not active in Slack" — auto-away after 10 min of desktop cursor inactivity or mobile app closed (manual override allowed) | Connection-driven: workspace-locally away — last WebSocket connection in this workspace > 1 hour ago. No cursor-activity tracking. |
| Email event types | Mentions, DMs, channel/workspace notifications, followed-thread replies, keyword matches | Mentions, DMs, room-wide `@everyone` mentions (only when an in-app row would be created) |
| Delivery shape | Bundled | Bundled |
| Delivery timing | Every 15 minutes or once an hour | Hourly or daily |
| User frequency preference | Yes | Yes: hourly or daily |
| Existing-user default | Slack-dependent; docs say email can be default when mobile notifications are not enabled | Off (`missed_email_enabled: false`) |
| Account/workspace email gate | n/a (managed-Slack only) | `account.email_notifications_enabled` defaults off |
| Thread-reply email | Yes, for followed threads | Deferred to v1.1+ (recipient addressing already exists; gated on bundle-volume telemetry) |
| Thread following | Explicit — "Follow thread" / "Get notifications for this thread" action; posting auto-follows | Implicit — thread membership is the equivalent. Posting in a thread auto-creates membership; parent room `involvement: everything` opts users into thread replies workspace-wide. No explicit "follow without posting" UI yet |
| Reactions / boosts email | No (Slack does not email reactions) | No — `:boost` is not in `EMAIL_TYPES` |
| Keyword alerts / highlight words | Yes — "My keywords" | Out of scope; "personal beats ambient" frame |
| Snooze / DND | Yes — manual, scheduled, mobile-timing windows | None. Master switches + per-room `involvement: :nothing` only |
| Per-channel notification setting | Yes — per-channel mute / mentions-only / all | Yes — per-room `Membership#involvement` (`everything`/`mentions`/`nothing`/`invisible`) |
| Per-channel email control | Yes — channel-level email toggle | Out of scope |
| Reply from email | Yes — replies post back into channel/thread | Deferred to v1.1+ |
| Product/news emails | Separate email subscription surface | Out of scope for notification routing |
| Weekly activity digest | Not found in public Slack notification docs | Admin-enabled weekly workspace recap; members default subscribed |
| Bounce / complaint suppression | Slack-managed | None in v1; webhook-driven suppression in v1.1 |

## Why Sabha is not copying Slack exactly

Slack's email notification model is a mature bundle system. That makes sense for Slack because it has a broad notification surface: mentions, DMs, followed threads, keywords, channel-wide mentions, channel-specific settings, mobile timing, snooze windows, and frequency preferences.

Sabha's goal is different: bring members back to an open community without making the product feel like a work-chat alarm system. Sabha copies Slack's bundled delivery shape, but uses calmer user-facing timing: hourly or daily rather than 15 minutes.

The hourly/daily choice is the compromise:

- It avoids emailing users who briefly disconnect and return.
- It keeps inbox volume lower for community members.
- It still gives users a familiar frequency choice.
- It leaves room for a separate weekly digest that brings less-active members back without acting like an urgent alert.

## Slack features Sabha v1 does not ship

The v1 plan is intentionally less capable than Slack. Each gap below is a deliberate choice, not an oversight:

- **Thread-reply email.** Slack emails replies in followed threads; Sabha doesn't in v1. A single active thread can produce 20 replies in a window, which would blow past the PRD's "calm timing, low volume" target. The `notification_bundle_items.kind` enum is intentionally `mention | direct_message` only for v1. The recipient set is already wired in `CreateThreadReplyNotificationsJob` (thread members + parent room `involved_in_everything`, minus already-mentioned), so v1.1 is mostly opting `:thread_reply` into `EMAIL_TYPES` and `notification_bundle_items.kind`. Revisit once v1 bundle-volume telemetry shows headroom.
- **Keyword alerts / highlight words.** Slack's "My keywords" lets users get notified when arbitrary terms appear. Sabha doesn't ship this and isn't planning to in v1.1 — keyword alerts are explicitly the *ambient* surface, which sits outside the v1 frame of "personal beats ambient." This is a v2 product question, not a v1.1 implementation question.
- **Reactions / boosts email.** Neither Slack nor Discord email reactions, and Sabha v1 doesn't either. `:boost` exists in the dispatcher vocabulary for in-app row creation only.
- **Snooze / DND.** Slack has manual snooze, scheduled DND windows, and mobile-quiet-hours. Sabha v1 has none of these — no `snooze_until` column, no scheduled-quiet-hours, no presence-as-snooze beyond `workspace_locally_away?`. Master switches (`missed_email_enabled`, `push_enabled`) and per-room `involvement: :nothing` are the v1 silencing levers. (PRD § Confirmed decisions #7.)
- **Per-channel email control.** Slack lets users opt a specific channel into email-only or mute-only treatment. Sabha v1 has no per-room email override; the room-level lever is `Membership#involvement`, which gates all channels uniformly via `effective_involvement`.
- **Reply-from-email.** Slack supports replying directly from notification email. Sabha defers this to v1.1+ — outbound is ~10% of the work; inbound (MX route, threading by `Message-ID`/`In-Reply-To`, sender authentication, attachment handling, tenant routing) is the other ~90% and overlaps zero with the v1 architecture.

These gaps are acceptable only if v1 is framed as **community reactivation email**, not as "Slack-compatible notification email." The weekly digest fills the reactivation half; the missed-notification bundle fills the personal half. Together they cover what a community product needs without inheriting Slack's full notification surface.

## Confirmed decisions

- New and existing users default `missed_email_enabled: false`.
- Missed-notification bundle frequency is user-selectable: hourly or daily.
- `@everyone` / room-wide mentions are notification-worthy, following Slack broad mentions — but only for recipients who would receive an in-app row.
- Weekly digest is admin-enabled at the workspace level (`account.weekly_digest_enabled` defaults off); members default subscribed (`weekly_digest_subscribed: true`) so flipping the admin switch reaches the existing membership immediately.
- Snooze / DND is not a v1 feature, in any form.
- Self-hosted email notifications stay disabled until sending-domain setup is complete (operator verifies a Resend domain).
- SaaS uses SES via `aws-sdk-rails`; self-hosted uses Resend via `resend-rails`. Both flow through the standard ActionMailer `delivery_method` API.
