# Email notifications PRD

**Status:** Draft.
**Date:** 2026-05-09.
**Related docs:** `docs/plans/email-notifications/NOTIFICATIONS-ARCHITECTURE.md` (current), `docs/plans/email-notifications/UNIFIED-NOTIFICATIONS-PLAN-REFERENCE.md` (superseded reference), `docs/plans/email-notifications/NOTIFICATIONS-SLACK-COMPARISON.md`.

## Product thesis

Email notifications should bring members back to discussions happening in a workspace without making Sabha feel like a work-chat app.

Sabha is primarily an open chat community product. Members are not expected to sit in it all day like Slack. The job of email is not to demand immediate action; it is to gently remind people that the community is alive, that someone addressed them, and that there is a reason to return.

The product target is:

- **Useful enough to recover missed conversations.**
- **Quiet enough not to become inbox noise.**
- **Familiar enough that Slack/Discord users understand it.**
- **Simple enough that community owners can trust the defaults.**

## Problem

Today, if a member is away from the workspace, important discussions can pass without any durable reminder outside the app. Push helps only when the browser/device subscription is working and the user is comfortable with push. In-app Activity is useful only after the user returns.

For open communities, this creates a retention problem: members drift away because they are not reminded when the community is active around them.

## Goals

- Bring members back when they are personally addressed.
- Reduce missed mentions and DMs for members who are not actively reading the workspace.
- Keep email volume low enough that members do not unsubscribe or mentally classify Sabha as noisy.
- Use bundled delivery, not one email per event.
- Use calm timing: hourly or daily bundles for personal alerts plus a separate weekly community digest.
- Support an admin-enabled weekly digest that reminds members what happened in the community.
- Make email easy to disable.
- Preserve the Activity tab as the complete in-app truth.

## Non-goals

- Do not become a full Slack notification clone.
- Do not email every room message by default.
- Do not make email a substitute for reading the app.
- Do not add per-room email controls in v1.
- Do not add keyword alerts in v1.
- Do not add marketing/newsletter subscriptions here; this PRD covers product-generated discussion emails only.
- Do not let weekly digests become admin-authored newsletters in v1; the digest is generated from workspace activity.

## Target users

- **Community members** who check the workspace occasionally and want to know when someone directly involves them.
- **Community hosts** who want members to return to discussions without manually nudging them.
- **Less active members** who may not install the PWA or enable push but still read email.

## Product principles

1. **Personal beats ambient.** Email should prioritize messages that involve the member: DMs, direct mentions, and high-signal room-wide mentions.
2. **Bundle before sending.** Multiple missed items should become one useful email, not a burst.
3. **Reminder, not alarm.** The tone and timing should suggest "there is something for you" rather than "respond now."
4. **Workspace context matters.** In SaaS, email reminds the member about a specific workspace/community.
5. **Easy exit.** Every email should provide a clear unsubscribe path and a settings link.
6. **Admins control community-wide email.** Personal missed-notification email is a member preference; weekly general-activity email is a workspace/admin choice with member opt-out.

## Proposed v1 behavior

### Two email surfaces

V1 has two planned email surfaces with different jobs:

- **Missed-notification bundles**: member-specific, near-term emails for DMs and mentions while the member is away.
- **Weekly activity digest**: admin-enabled community reminder that summarizes what happened in the workspace over the week.

These should not share copy, timing, or product framing. The first says "someone addressed you." The second says "your community has been active."

### Competitive reference

Slack:

- Email notifications are bundled and can be delivered every 15 minutes or once an hour.
- Slack's notification docs say users can be alerted for DMs, mentions, channel notifications, and replies to followed threads when they are not active.
- Slack does not appear to offer a general weekly workspace activity digest in the public notification docs.

Discord:

- Discord separates several email categories, including communication emails for missed calls/messages, social emails, announcements/updates, tips, and recommendations.
- Discord's closest product analogue to a general activity digest is Highlights: occasional notifications for key server moments such as popular messages, events, announcements, friend activity, and other activity selected partly from reactions/replies/events and partly from personalization.

Product takeaway for Sabha:

- Use Slack-like bundled delivery for missed personal notifications, but choose calmer hourly/daily timing for an open community.
- Treat broad room-wide mentions as notification-worthy, following Slack's `@everyone` / `@channel` behavior.
- Do not copy Discord Highlights for weekly digest selection. Slack does not have a general weekly workspace digest, so Sabha's weekly digest should stay conservative: a simple recap of accessible workspace activity, not personalized algorithmic highlights.

### What generates missed-notification candidates

Email candidates are created for:

- Direct messages.
- Direct `@mentions`.
- `@everyone` / room-wide mentions, only when the user would receive an in-app mention row.

Deferred:

- Thread replies.
- Boosts.
- All regular room messages.

### When candidates are created

At message creation time, Sabha decides whether the user is eligible for email:

- User is away from the workspace.
- User has email notifications enabled.
- Workspace/account email feature flag is enabled.
- User has a verified email address.
- User is active, not banned, not deactivated, and not a bot.
- Sender and recipient are not blocked in either direction.
- Message and room are active.
- The user's room membership receives that activity type.
- Global mode `nothing` suppresses email unless the room is explicitly set to `everything`.

Eligible events are added to a pending email bundle instead of being sent immediately.

### Delivery shape

Email notifications are bundled per user per workspace.

A bundle email should answer:

- Which workspace is this from?
- What did I miss?
- Who addressed me?
- Where should I click to rejoin the discussion?

The email should group missed items by room or conversation. It should not try to reproduce the full app UI.

### Delivery timing

Use calm bundle timing:

- Default: hourly bundles while the user remains away.
- Optional setting: daily bundles.
- If the user returns before the bundle is sent, the bundle is canceled or skipped.

This gives email enough delay to avoid noise from brief disconnects and keeps Sabha from feeling like a work-chat alarm system.

### Send-time revalidation

Before sending a bundle, Sabha rechecks whether each item is still eligible:

- User may have returned.
- User may have disabled email.
- Sender may have been blocked.
- Message may have been deleted.
- Room or membership may no longer be active.

If no items remain eligible, no email is sent.

### Weekly activity digest

The weekly digest is planned for v1 as an admin-enabled workspace feature.

Purpose:

- Bring less-active members back to the workspace.
- Show that the community is alive.
- Surface discussions that are worth catching up on without implying urgency.

Admin behavior:

- Workspace admins can enable or disable the weekly digest for the workspace.
- Weekly digest is off by default; admins choose whether to enable it.
- Admins should see a short preview/explanation before enabling: the digest is generated from workspace activity, not manually authored.

Member behavior:

- Members can unsubscribe from digest emails separately from missed-notification emails.
- Banned, deactivated, bot, and unverified-email users do not receive digests.

Digest content should include:

- Workspace/community name.
- A short recap of recently active rooms or discussions the member can access.
- Room-wide mentions and other notification-worthy activity first.
- A small number of recent public/shared discussion excerpts.
- A CTA back to Activity.
- Manage email preferences and unsubscribe links.

Digest content should avoid:

- Listing every message.
- Ranking members competitively.
- Discord-style personalized Highlights.
- Creating FOMO-heavy or guilt-heavy copy.
- Surfacing private/direct-message content.
- Surfacing rooms the member cannot access.

Timing:

- Weekly.
- A consistent workspace-local send day/time, chosen by product default first; admin customization can come later.
- No more than one weekly digest per member per workspace.

### Defaults

Confirmed:

- Existing users: email notifications off by default during rollout.
- New users: email notifications off by default.
- Workspace/account feature flag: off by default until deliverability is proven.
- Weekly digest: off by default; workspace admins choose whether to enable it.

The product tension: default-off avoids surprise email, but weakens the goal of bringing members back. A later rollout may need an in-product prompt or a new-user default once sender reputation and unsubscribe behavior are understood.

## Email content

Each bundle should include:

- Workspace/community name.
- A generic subject that makes the workspace source clear without exposing sender or room names.
- A compact summary of missed DMs/mentions.
- Sender names and room names can appear inside the email body when needed, but not in the default subject line.
- Primary CTA: open Activity.
- Secondary link: manage notification settings.
- Unsubscribe link.

Weekly digest emails should have a different content shape:

- Subject should frame the workspace recap, not a personal alert.
- Body should summarize a few high-signal public/shared discussions.
- CTA should invite catching up, not immediate response.
- Unsubscribe should distinguish "weekly digest" from "mentions and DMs."

Tone:

- Warm and plain.
- No urgency theater.
- No "you are falling behind" language.
- No gamified engagement copy.

Example subject directions:

- `New mentions in {Workspace}`
- `You have new messages in {Workspace}`
- `New activity in {Workspace}`

## Settings

Minimum v1 settings:

- Email notifications: on/off.
- Email frequency: hourly / daily.
- Weekly digest: on/off for admins at the workspace level.
- Weekly digest subscription: on/off for members.

Other notification controls can live alongside email, but this PRD does not require a large Slack-style settings surface.

## Success criteria

Quantitative:

- Members who receive email return to the workspace at a higher rate than similar members who do not.
- Low unsubscribe rate.
- Low spam complaint / bounce rate.
- Bundle emails produce meaningful click-through to conversations or Activity.
- Weekly digests produce return visits from less-active members.
- Email volume per active recipient stays within an acceptable range.

Qualitative:

- Members describe emails as helpful reminders, not nagging.
- Community hosts feel email helps revive participation.
- Community hosts understand and trust what the weekly digest sends.
- The feature does not make Sabha feel like corporate work chat.

## Risks

- Email becomes noisy and members unsubscribe.
- `@everyone` emails become too broad for large communities.
- Default-off rollout leads to low adoption.
- PII in subjects can expose sensitive room names or sender names in inboxes.
- Self-hosted operators may not configure deliverability correctly.
- Bundling adds more product and implementation complexity than one-off delayed emails.
- Weekly digest quality may be poor in quiet workspaces or noisy in very active workspaces.
- Admin-enabled digest can surprise members if member-level controls are unclear.
- **No bounce or spam-complaint suppression in v1.** v1 ships without webhook-driven suppression of permanently undeliverable addresses. Hard-bouncing recipients continue to receive mail until v1.1 lands provider webhook ingestion. Bounded by the account-level email feature flag defaulting off, but operators flipping it on without bounce monitoring carry sender-reputation risk.

## Confirmed decisions

1. **New-user email default**: off.
2. **Email frequency**: user-selectable between hourly and daily.
3. **Primary CTA**: Activity.
4. **Subject privacy**: generic subjects by default.
5. **Self-hosted posture**: email notifications disabled until sending-domain setup is complete.
6. **Weekly digest workspace default**: off; admins choose whether to enable it.
7. **Snooze**: out of scope; email settings stand on their own.
8. **Room-wide mentions**: `@everyone` / room-wide mentions create missed-notification email candidates, following Slack's broad-mention behavior, but only for recipients who would receive an in-app mention row.
9. **Weekly digest selection**: follow Slack by not adopting Discord-style personalized Highlights. Since Slack does not provide a general weekly workspace digest, Sabha's digest is a conservative recap of accessible recent room activity, with notification-worthy activity first.
10. **Digest sends regardless of member activity**: a subscribed member who was active every day this week still receives the weekly digest. The on/off subscription is the only gate, plus 6-day dedup. A presence-aware "only-if-inactive" gate was rejected because it weakens the simple opt-in mental model and creates subscriber confusion ("I subscribed but didn't get one"). Members who find the digest noisy can unsubscribe from digest only — separate from missed-notification email.
11. **SaaS sender domain is shared across all workspaces in v1.** Workspaces cannot configure their own sending domain in v1; all email sends from a shared Sabha domain with the workspace name in the From display name and Subject line. Per-workspace BYO sending domain is deferred to v1.1.

## Product position

Sabha should borrow Slack's bundling and timing expectations, but not Slack's notification sprawl.

The right product shape for missed notifications is:

> "When you are away, Sabha occasionally emails you a bundled reminder of the conversations that need your attention."

The right product shape for weekly digest is:

> "Once a week, if the workspace admin enables it, Sabha sends a calm recap that helps members remember and rejoin the community."

Not:

> "Sabha emails every notification as soon as it happens."

And not:

> "Sabha becomes a full work-chat notification control panel."
