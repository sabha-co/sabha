# Planned notification changes compared to Slack

**Status:** Companion note for `NOTIFICATIONS-ARCHITECTURE.md`.
**Verified:** 2026-05-09.
**Purpose:** Make the Slack comparison explicit so the implementation plan does not quietly inherit Slack-shaped assumptions we are not actually shipping.

## Slack baseline

Slack's public help docs describe two different email surfaces:

- **Notification emails**: missed-activity emails sent when a user is not active in Slack. Slack says these can alert users about mentions, DMs, and replies to threads they follow. Slack bundles these emails and delivers them every 15 minutes or once an hour, depending on user preference.
- **Email news and updates**: product/news/tip/feedback emails. These are managed separately under "Email news and updates" and are not the same thing as missed-message notification email.

Sources:

- Slack notification guide: https://slack.com/help/articles/360025446073-Guide-to-Slack-notifications
- Slack notification configuration: https://slack.com/hc/en-us/articles/201649273-Configuring-email-notifications
- Slack email subscriptions: https://slack.com/intl/en-in/help/articles/360003868571-Manage-your-Slack-email-subscriptions

## Sabha v1 plan

Sabha v1 is Slack-inspired, not Slack-equivalent.

The planned v1 behavior:

- Email for `:mention`, `:direct_message`, and `@everyone` / room-wide mentions when the user would receive an in-app mention row.
- Email only when the user is away from the current workspace.
- Existing users default to `email_when_away: false`.
- Account/workspace email feature flag defaults off.
- Missed-notification emails are bundled.
- Users can choose hourly or daily missed-notification bundles.
- Weekly activity digest is available when a workspace admin enables it.
- Thread-reply emails are deferred.

## Comparison

| Area | Slack | Sabha v1 |
|---|---|---|
| Email trigger | User is not active in Slack | User is away from the current workspace |
| Email event types | Mentions, DMs, channel/workspace notifications, followed-thread replies | Mentions, DMs, room-wide mentions |
| Delivery shape | Bundled | Bundled |
| Delivery timing | Every 15 minutes or once an hour | Hourly or daily |
| User frequency preference | Yes | Yes: hourly or daily |
| Thread-reply email | Yes, for followed threads | No, deferred |
| Existing-user default | Slack-dependent; docs say email can be default when mobile notifications are not enabled | Off |
| Product/news emails | Separate email subscription surface | Out of scope for notification routing |
| Reply from email | Slack supports replying from notification email | Out of scope |
| Weekly activity digest | Not found in public Slack notification docs | Admin-enabled weekly workspace recap |

## Why Sabha is not copying Slack exactly

Slack's email notification model is a mature bundle system. That makes sense for Slack because it has a broad notification surface: mentions, DMs, followed threads, keywords, channel-wide mentions, channel-specific settings, mobile timing, and frequency preferences.

Sabha's goal is different: bring members back to an open community without making the product feel like a work-chat alarm system. Sabha copies Slack's bundled delivery shape, but uses calmer user-facing timing: hourly or daily rather than 15 minutes.

The hourly/daily choice is the compromise:

- It avoids emailing users who briefly disconnect and return.
- It keeps inbox volume lower for community members.
- It still gives users a familiar frequency choice.
- It leaves room for a separate weekly digest that brings less-active members back without acting like an urgent alert.

## Product tradeoffs

The v1 plan is intentionally less capable than Slack in these ways:

- Thread replies do not email.
- Existing users may not discover the feature unless we add a separate rollout/nudge.

Those are acceptable only if v1 is framed as community reactivation email, not as "Slack-compatible notification email."

## Confirmed decisions

- New users default email notifications off.
- Missed-notification bundle frequency is user-selectable: hourly or daily.
- `@everyone` / room-wide mentions are notification-worthy, following Slack broad mentions.
- Weekly digest is off by default and admin-enabled.
- Self-hosted email notifications are disabled until sending-domain setup is complete.
