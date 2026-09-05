# Plan: Room info panel

**Date:** 2026-09-05 · **Branch:** `redesign-v2` · **Design reference:** Pencil “Screens · Roster audit”

## Decision: simplify Room info and reserve space for huddles

On 2026-09-05, the owner decided to remove the member sections and management
actions from the contextual panel. Room attendance was judged insufficiently
useful here; removing it also reduces loading work. The panel's spare space is
reserved for a future huddle feature. This is a product decision, not a temporary
empty state. Do not add a huddle placeholder or implement huddles in this change.

Members are viewed and managed through **Room settings**. Room info retains a
Settings link as the route to those tasks. Leave room also stays in settings.

This supersedes the earlier proposal to expand the roster with Here now,
Recently here, All members, quick profiles, member totals, Manage members and
Leave room. It also cancels presence resolution and periodic roster refreshes.
The existing internal `roster` route and CSS/controller naming may stay; the
user-facing name remains **Room info**.

## Final panel anatomy

1. Header: room type glyph, room name and Close room info.
2. Room description, when present.
3. Favorite and Settings.
4. Notifications: a labelled dropdown with Mentions only, All notifications and
   Notifications muted. DMs retain their existing notification toggle.

No member totals, attendance counts, activity groups, member disclosure, quick
profiles, Manage members button or Leave room button appear in this panel.
No roster data model, member pagination variant, presence-dot surface or polling
is needed. Room settings retains its existing member list and permissions.

## Header controls and panel behavior

- Keep both the clickable member avatars and `icon--panel-right`, as explicitly
  requested by the owner. Remove the redundant users icon on web; native keeps
  its existing member affordance. Phones show the compact panel-right icon.
- Both web controls toggle Room info and reflect its expanded state through
  `aria-expanded`, `aria-controls` and a restrained active tint.
- Focus the panel heading on an explicit open and return focus to the opener on
  close. Escape dismisses an open notification popup before closing the panel.
- The shared panel's accessible name follows its content: Room info, Thread or
  Post. Nested frame loads must not reopen or refocus the containing panel.
- Remember an explicitly opened Room info panel across desktop room navigation
  at widths of at least 1160px. Store this preference per account and user on
  the device, including the tenant identifier in SaaS keys because local record
  IDs can repeat across workspaces. Omit the key on public pages where the user
  or account is absent. Explicit close clears it. Never automatically open overlays or
  replace a deep-linked thread/post.
- Keep the existing responsive layout: docked at 1160px and above, overlay below
  that, and full column below 500px. Preserve existing light/dark tokens.

## Notification updates and cleanup

Use the existing anchored popover and involvement options. The initial render,
HTTP update response and broadcast replacement must all keep the same dropdown;
selecting an option must not revert it to the former cycling button. Support
keyboard selection and mark the current option.

Dispatch involvement broadcasts through `Turbo::StreamsChannel`. Broadcasting
from the controller itself creates a tag builder that leaks into the subsequent
response's view assigns, breaking nested block capture. Controller tests must
assert that the options remain **inside** the menu in both the HTTP response and
broadcast output; browser tests cover reopening it after a selection.

Remove the generic `/rooms/:id/edit` route, which points at an absent action.
Continue using the typed Settings routes through the existing helper.

## Superseded workstreams

| Earlier workstream | Final decision |
| --- | --- |
| A: Room totals, full member list and empty state | Removed; use Room settings |
| B: Attendance groups and resolved presence dots | Removed; no roster presence queries |
| C: Member quick profiles | Removed from Room info; existing profiles elsewhere stay |
| D: Header entry and toggling | Keep avatars and panel-right; both toggle |
| E: Panel accessibility | Keep heading focus, opener restoration and accurate labels |
| F: Labelled notification control | Keep dropdown and consistent update rendering |
| G: Freshness and persistence | Remove polling; keep desktop-only explicit-open persistence |
| H: Footer and route cleanup | Remove footer actions; keep dead-route cleanup |

## Verification

- Controller tests: Room info content and access, Settings link, notification
  response and broadcast structure, typed settings routes, existing membership
  operations and permissions.
- Browser tests: both header triggers, notification selection and keyboard
  navigation, Escape behavior, focus restoration, desktop persistence and
  overlay widths, shared thread/post behavior, and existing settings flows.
- Capture light and dark at 1400px, 1100px and 390px. Verify the simplified panel
  has no member-loading frames or presence refresh work.
- Pencil captures may be added beside the audit frame when its MCP connection is
  available. Use live browser screenshots for implementation verification.

## Out of scope

Huddles, live roster presence, an always-open member column, role sections,
group-DM participant redesign, schema changes and changes to connection semantics.
Push and PR require an explicit request.
