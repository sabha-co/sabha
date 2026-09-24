---
title: Your communities in one place — sabha.co as the switcher for self-hosted Sabha
type: feat
status: ready
date: 2026-09-23
builds_on: "#194 Sabha protocol (merged 2026-09-23; supersedes #177 and #178), #193 workspace caps (in review, not a prerequisite)"
---

# Your communities in one place

## The idea in one paragraph

People don't belong to one Sabha. They're in a couple of workspaces on sabha.co, their open-source project's self-hosted Sabha, a friend's Sabha Cloud droplet. Today each of those is a separate site with a separate login and nothing ties them together. This plan makes **sabha.co the place that remembers every Sabha you've joined**, on the web and in the desktop and mobile apps, so switching between them is one click. Any self-hosted community works from day one, without its admin doing anything. Communities whose admin connects them to sabha.co also get a shortcut: "Continue with sabha.co" instead of another password.

## Who this is for

**A member** of several communities.
> "I joined three Sabhas. I want them in one list, on my laptop and my phone, and I don't want to hunt for URLs."

**A self-hosted admin.**
> "I want my members to find us easily and sign in without friction, but my community keeps its own accounts. Nobody outside decides who gets in."

**A Sabha Cloud customer.**
> "I just bought a droplet. It should already be in my list when I open sabha.co."

## How it works for a member

### Joining a community

You accept an invite to `chat.acme.org` and create an Acme account the normal way. Acme then offers **"Add Acme to your sabha.co list"** (you can dismiss it for good). You can also paste `chat.acme.org` into sabha.co or the app yourself. Either way sabha.co shows you the community's name *and its address* to confirm, and it appears in your list. No admin involved.

The community must run a Sabha version that publishes its manifest; for an older one, sabha.co says the community needs to update Sabha.

If Acme's admin has connected it to sabha.co, the join page also offers **"Continue with sabha.co"**. You approve once ("Allow Acme to see your name and email?"), you get an Acme account without a new password, and Acme lands in your list in the same step.

### Switching on sabha.co (web)

Your list sits in the workspace selector, mixed with your sabha.co workspaces, in the order you choose. A self-hosted entry is a link to that community's own site. If you've signed in there before in this browser, you go straight in. If not, you see its login page, with the sabha.co shortcut when it has one.

On the web, sabha.co can't see whether you're signed in to another site, or its unread counts; browsers deliberately block that. Here the list is a **launcher**.

### Switching in the desktop and mobile apps

The desktop app (Electron) and the mobile app (Hotwire Native) both show each community's own web UI, so they work the same way. Sign in to sabha.co in the app once and your whole list arrives. Each community then needs its own session in the app, obtained in one of two ways:

- **Community with the shortcut:** one tap or click. A system browser sheet opens briefly, sabha.co confirms it's you (you already approved Acme once, so there's no screen to answer), and you're handed back to the app. If you aren't signed in to sabha.co in that browser, you sign in there first.
- **Community without it:** its own login, shown inside the app, once per device.

Because the app holds a session with every community, it's a **real switcher**: unread badges, notifications from all of them, and instant switching. The web can't do this; the apps can. On the phone, notifications also need the push relay (see Not in scope).

### A new laptop or phone

Your list is already there. Communities with the shortcut need one tap each; others need one login each. Nothing about your other devices changes.

### Leaving or tidying up

- **Hide** a community from the list: it stays hidden until you add it again or sign in with the shortcut.
- **Can't reach it?** If a community is down or moved, its entry is marked as unreachable, and it keeps its last known name until it comes back or you remove it.
- **Remove** it: it's gone from your list and sabha.co forgets it. Your Acme account is untouched.
- **Disconnect** the shortcut: sabha.co stops vouching for you to Acme. Next time it asks for permission again.
- **Settings → Your communities** shows everything sabha.co remembers for you, and lets you clear it.

## How it works for an admin

**Doing nothing is fine.** Members can already add your community to their sabha.co list. Your community's login, members and data stay yours. sabha.co only reads your public name and logo.

**Connecting to sabha.co (optional, one-time)** adds the "Continue with sabha.co" shortcut:

1. On sabha.co, paste your community's address. sabha.co checks it's a Sabha server and gives you a secret, shown once.
2. Put the secret in your community's settings (`SABHA_HUB_SECRET`) and restart.
3. Click **Verify** on sabha.co right after the restart. It checks for a proof that only your server can publish, and switches the shortcut on.

After that:

- Password and email-code login keep working exactly as before. The shortcut is one more option.
- **You still decide who gets in.** By default someone new needs your invite link, even with the shortcut. You can open it up (`SABHA_HUB_AUTO_PROVISION=true`).
- An existing member is never merged with a sabha.co account just because the emails match. They connect it from their own profile.
- Signing out of your community signs them out of your community only.
- You can rotate the secret or disconnect from sabha.co at any time. Rotating is the same three steps; the shortcut stops working between your restart and Verify, so do them together.
- If whoever set up the pairing has left, anyone who controls the server can pair again. A new pairing that passes Verify replaces the old one.

A community that uses its own single sign-on (`AUTH_METHOD=sso`) keeps that as its only way in; the shortcut isn't offered.

## How it works for Sabha Cloud

When a droplet is created, Sabha Cloud connects it to sabha.co and adds it to the owner's list. The owner's first sign-in and every later "Continue with sabha.co" are the same account on the droplet, with no linking step.

## Principles

1. **Your list is yours.** Only you add to it: by pasting an address, by accepting a prompt a community shows you, by approving the shortcut, or by owning a Sabha Cloud droplet. A community can't add itself to your list.
2. **Sessions stay on your device.** sabha.co never stores a login for another community. A new device signs in to each community on its own. This is the line we don't cross: a sabha.co that held keys to every community would be one breach away from exposing all of them.
3. **Communities own their accounts.** The shortcut is a convenience the admin chooses. It never replaces their login, their invite rules, or their sign-out.
4. **Ask before sharing who you are.** sabha.co tells a community your name and email only after you approve it, once per community.
5. **Never match by email.** Accounts are linked only when their owner, signed in, asks for it.

## What's in scope

**The list (sabha.co)**
- L1. A per-person list of self-hosted communities, shown in the workspace selector alongside sabha.co workspaces, reorderable across both, not counted toward any sabha.co workspace membership limit (such as the one proposed in #193). Up to 100 entries per person, with a per-hour limit on adds.
- L2. Add by pasting an address. sabha.co checks it's a Sabha server via its public manifest and shows the community's own name and logo, refreshed in the background rather than copied once. Communities too old to publish a manifest get a clear "needs to update Sabha" message.
- L3. Add from a community: any self-hosted Sabha can show "Add to your sabha.co list" after sign-in. It's a link to sabha.co carrying the community's address; sabha.co asks the person to confirm. Members can dismiss it for good; it isn't shown to members who arrived through the shortcut (they're already listed), and the admin can switch it off.
- L4a. Every entry shows the community's address under its name, and the add and consent screens show it prominently, so a look-alike name can't pass as another community.
- L4b. Logos are copied to sabha.co and served from there, so a community never sees who is viewing its logo in someone's list.
- L4c. A community that can't be reached is marked unreachable and keeps its last known name.
- L4d. Names are display only and may repeat: a self-hosted "Rust Club" and a sabha.co "Rust Club" are different entries, told apart by the address under the self-hosted one. A self-hosted community is identified by its normalised address; pasting `HTTPS://Chat.RustClub.org:443/` finds the same entry as `https://chat.rustclub.org`.
- L4e. Pasting sabha.co itself is refused; pasting a sabha.co workspace address (`sabha.co/1000121`) goes to that workspace's normal join flow instead of the remote list. Sabha Cloud droplets on `*.sabha.co` subdomains are self-hosted communities and can be added.
- L4f. If the pasted address differs from the address the community calls itself, the add screen says so ("this community calls itself chat.rustclub.org") and offers to add that one instead. Both stay allowed; sabha.co never merges two addresses on its own.
- L4. Entries added through the shortcut or by Sabha Cloud appear automatically.
- L5. Hide, remove, and a "Your communities" settings page listing everything remembered, with a clear-all.
- L6. The list is served to the desktop and mobile apps through the protocol's destination catalog (`GET /api/destinations`, #194).

**The shortcut: "Continue with sabha.co"**
- S1. Optional pairing for admins: paste address → secret shown once → set it → Verify.
- S2. The button on the community's sign-in and invite pages, alongside its own login.
- S3. A consent screen on sabha.co the first time, per person and community.
- S4. The community's own rules still apply: invite-only by default, no email matching, linking only from a signed-in profile with a recent password or email-code check, and no removing a member's last way to sign in.
- S5. Admins can rotate the secret or disconnect; members can disconnect from their settings. A new verified pairing replaces the old one, so control of the server, not the original account, owns the pairing.
- S6. Sabha Cloud connects droplets and adds them to the owner's list at provisioning.

**The apps: desktop (Electron) and mobile (Hotwire Native)**
- A1. After one sabha.co sign-in, the app shows the whole list.
- A2. Per-community sign-in: the shortcut through the system browser where available (on mobile, `ASWebAuthenticationSession` / Custom Tabs), otherwise the community's own login inside the app. Both end in a **cookie** session for that community's origin: an Electron partition on desktop, the web view cookie store on mobile (#194's PKCE hand-off and session claim).
- A3. Desktop: unread badges and notifications per community from each community's `DesktopChannel` (#194); the community's admin must have `DESKTOP_NOTIFICATIONS_ENABLED=true`, which is off by default.
- A4. Mobile: the in-page workspace rail and WebPush bell are hidden for `hotwire_native_app?`, as #194 does for the desktop app, since the native switcher replaces them. Every community in the list opens inside the app, in its own `Navigator` (Hotwire Native otherwise opens other domains in an external browser). Unread badges come from the catalog on foreground; push notifications wait for the push relay.
- A5. Mobile path configuration (iOS and Android) is served by sabha.co and applies to every community, since all Sabha servers share routes.

## Not in scope

- Showing another community's pages inside sabha.co on the web. Entries are links.
- Unread badges in the web list. Only the apps can show them.
- sabha.co storing sessions or tokens for other communities, on any device.
- Communities sending their member lists to sabha.co. sabha.co only knows what each person adds.
- Changes to custom single sign-on (`AUTH_METHOD=sso`).
- Syncing profiles beyond name and avatar hints when an account is created.
- **Mobile push notifications.** Apple's and Google's push credentials belong to the Sabha app, so a self-hosted community can't push to it directly; it needs a push relay run by Sabha, plus a way for each community to receive the device token. That relay is its own plan. Until then the mobile app shows badges when it opens.

## Decisions

Settled with the owner on 2026-09-23:

- **The list is the product; the sign-in shortcut is optional.** Any member can add any community; pairing speeds up sign-in but isn't required to be listed.
- **Shared secret per paired community**, not a Chatto-style public client. It reuses the single sign-on code Sabha already has, and the origin proof closes the pairing gap. The secret-free design stays a possible later swap underneath the same button and screens.
- **Invite-only by default** for new members arriving through the shortcut.
- **No shortcut under `AUTH_METHOD=sso`.** Custom single sign-on stays exclusive.
- **An admin disconnecting from sabha.co keeps members' entries.** Each entry falls back to a plain one (no shortcut, the community's own login); only the stored consent is dropped.
- **The "Add to your sabha.co list" prompt is on by default**, with an admin setting to hide it.

## Build order

Each step ships on its own and is useful by itself. #194 is merged and covers everything the plan needs. #193 (workspace caps) is still in review; it isn't a prerequisite, but step 2 touches the same selector, reorder and join code, so whichever lands second rebases.

1. **Community manifest: name, logo and address** (instance, after #194). `api/manifests/show.json.jbuilder` adds a `community` block with the account's name, logo URL and its own canonical URL (`Branding.app_url`, from `APP_HOST`), so lists show "Acme", not "Sabha", and sabha.co can spot a second address. #194 defers exactly this.
2. **The list on sabha.co** (hub; overlaps #193). Add by address, selector entries, hide/remove, reorder across workspaces and communities, "Your communities" settings. **This alone gives every member a switcher.**
3. **"Add to your sabha.co list" prompt** (instance, after 2). The link, dismissal, the confirm page on sabha.co, the admin toggle.
4. **The shortcut, community side** (instance, after #194). The button, the `issuer` column, link-from-profile, invite and last-method rules, `hub_proof` in the manifest.
5. **The shortcut, sabha.co side** (hub, after 2 and 4). Pairing and Verify, lookup by address, the consent screen, rotate and disconnect.
6. **Sabha Cloud** (hub platform API + `sabha_cloud`, after 5). Connect droplets and add them to the owner's list at provisioning.
7. **Desktop app** (catalog in this repo after 1 and 2; then `sabha-desktop`). The list in the app, per-community sign-in, badges.
8. **Mobile app** (Hotwire Native; path configuration in this repo, then `sabha-mobile`, after 1 and 2). The native switcher, the route handler that keeps listed communities in-app, per-community sign-in, and iOS and Android path configuration served by sabha.co.

---

# Technical design

## Current code this builds on

- `Account` owns `AUTH_METHOD` (`app/models/account.rb`). `Sso::BaseController`, `Sso::HandshakesController` and `Sso::CallbacksController` are the single sign-on consumer. `SingleSignOnRecord` resolves users, unique on `external_id` and on `user_id`. `User.sign_in_with_sso!` is the entry point, and `User` has `has_one :single_sign_on_record`.
- `SessionsController` and `UsersController` redirect to the handshake when `Account.sso_auth?`. `UsersController#redirect_to_sso_login` is the only place `pending_join_code` is stored.
- `FirstRun.auto_bootstrap_from_sso` creates a Sabha Cloud droplet's first admin and their `SingleSignOnRecord` from a sabha.co payload.
- `Sso::ProviderClient` is sabha.co's env-driven client registry. It tries every client's secret, supports wildcard return hosts with an exact-claim guard, and defaults the return path to `/session/sso/callback`.
- `Saas::SingleSignOnsController#show` returns the identity as soon as the user is signed in, with no consent. Its payload is `external_id: "global_identity:#{id}"`, email, name, `require_activation: !verified?`.
- #194 (superseding #177 and #178) adds the Sabha protocol, major 1 (`Sabha::PROTOCOL_MAJOR`):
  - **General part, any client:** `GET /api/manifest` (unauthenticated; protocol major, product identity from `Branding.app_name`, default "Sabha", sign-in path, catalog path) and `GET /api/destinations` (signed in; one branded peer when self-hosted, the person's ordered active workspaces in SaaS). Both are jbuilder views under `API::ProtocolController`, which answers 415 unless the request sends `Sabha-Protocol-Major`.
  - **App sign-in hand-off (both apps):** the `Handoff` concern on `Sso::HandshakesController` and `Sso::CallbacksController`. The app opens `/session/sso` in the system browser with `handoff`, `handoff_nonce`, `handoff_origin` and a PKCE `code_challenge`; after sign-in the community issues a five-minute `Session::Claim` (`session_claims`) and redirects to `sabha://session-claim`; the app redeems it at `POST /api/session_claim` with the `code_verifier`, which starts a **cookie** session for that origin. Every handshake clears a stale hand-off, and `return_to` must be a local path. SaaS has no claim path; the app signs in to sabha.co inside its own session, so `Saas::SingleSignOnsController#show` has no desktop branch.
  - **App detection:** the desktop app sends `Sabha-Client: desktop` (`platform.desktop_app?`), a layout hint only; it hides the SaaS workspace rail (`show_workspace_selector?`) and the WebPush bell. Hotwire Native mobile is detected by its user agent (`hotwire_native_app?`).
  - **Sign-in entry:** `Authentication#sign_in_entry_path` is where a signed-out browser is redirected and what the manifest advertises as `sign_in_path` (`/session/new`, or the SSO handshake in custom-SSO mode).
  - **Desktop layer:** `DesktopChannel` and desktop notifications, the only parts still named for the desktop.
  - **Notifications:** `DesktopChannel` per user with badge snapshots from `User#badge_count`, off by default behind `DESKTOP_NOTIFICATIONS_ENABLED`.
- `User` already has a serialized `preferences` column, usable for remembering the dismissed list prompt.
- #193 (in review) proposes `MAX_MEMBERSHIPS` over `workspace_memberships.user_active` and would stop hiding the workspace selector in the desktop app; if it lands, revisit decision 13 so remote entries aren't shown twice on desktop. `WorkspaceMembership.reorder_for_identity` matches workspace external ids against `tenant`.
- `RestrictedHTTP::PrivateNetworkGuard` resolves and pins a public IP for link previews.
- Nothing uses ActiveRecord encryption yet, and there is no credentials file.
- `sabha_cloud` reuses `SSO_PROVIDER_URL`/`SSO_SECRET` for first-admin bootstrap, so a customer's own SSO and bootstrap can't coexist. The new `SABHA_HUB_*` vars avoid extending that conflict.

## Prior art: Chatto

Chatto (`~/dev/chatto`, with its identity service Authling) is the reference for multi-server clients and coexisting sign-in methods.

Adopted:
- External identities keyed by issuer plus subject; email is never a match key.
- Linking starts from a signed-in session with fresh auth; there is no email merge at login.
- A passwordless account can't remove its last sign-in method.
- Consent per user and client, remembered and revocable.
- Client identity proven by its own origin (Chatto's CIMD; our `hub_proof`).
- Server name and logo read from the server's public profile and refreshed, not stored once.
- Sessions stay device-local, and sign-out is local.

Diverged:
- **A list synced across devices.** Chatto synced its server list through Authling (ADR-064), then made it device-local (ADR-074), because Authling was a background identity service and a server list is preference data. sabha.co is a product people already use, and it already renders the selector, so a remembered list fits it. We keep Chatto's rule that sessions never sync, and its lesson that a listed server doesn't imply a session there.
- **Shared secret instead of CIMD** for the shortcut (see Decisions).

## Key technical decisions

1. **Mirror `Workspace` / `WorkspaceMembership`.** A `RemoteWorkspace` is one self-hosted community, one row per origin, shared by everyone who lists it: its name and logo are refreshed once for all of them, and its active pairing (secret, status) lives on the same row. A `RemoteWorkspaceMembership` is one person's list entry: source, position, hidden, and the shortcut consent timestamp. It never holds credentials. `GlobalIdentity` gets `has_many :remote_workspace_memberships` beside `has_many :workspace_memberships`.
2. **Manifest probe with network guards.** Every fetch of a community's manifest (adding to a list, pairing, Verify, background refresh) goes through `RestrictedHTTP::PrivateNetworkGuard`: pinned IP, no redirects, short timeout, body limit, HTTPS only, no private or special-use destinations outside development. The fetch calls `GET /api/manifest` with `Sabha-Protocol-Major: 1` and carries no user information. A 404 or a response without a protocol major means a Sabha from before #194 (or not Sabha); a 415 means a different protocol major, shown as "needs to update Sabha". The logo is fetched the same way, type-checked (PNG, JPEG, WebP, GIF) and capped at 64 KB, and stored as bytes on the `RemoteWorkspace` row (`logo_data`, `logo_content_type`). It can't be an Active Storage attachment: with `connection_class = "ApplicationRecord"`, Active Storage blobs are tenanted and live in each workspace's database, and the untenanted database has no Active Storage tables. sabha.co serves the bytes from its own untenanted logo endpoint with long cache headers; its pages never load a community's image directly.
3. **"Add to your list" prompt is a plain link.** `https://sabha.co/remote_workspaces/new?origin=<origin>`. sabha.co signs the person in if needed, probes the origin, and asks them to confirm. The community learns nothing back, and no protocol or secret is involved. The community shows it only in self-hosted mode, stores a member's dismissal in `User#preferences`, and skips it for users who have a sabha.co link (they're already listed).
4. **The shortcut is an additional provider, not a mode.** It's on when `SABHA_HUB_SECRET.present? && !Sabha.saas?`, alongside `password` and `otp`, and hidden under `AUTH_METHOD=sso`. The community-side routes (`/session/hub`, `/session/hub/callback`, `hub_link`, `hub_list_prompt`) are declared `unless Sabha.saas?`, the way #194 declares the session-claim route, so they don't exist on sabha.co's tenanted workspaces at all.
5. **Reuse the DiscourseConnect consumer through a provider object.** `Sso::Provider` (`issuer`, `url`, `secret`) is built as `.custom` from `SSO_*` or `.hub` from `SABHA_HUB_*`. The route picks it: `/session/sso` or `/session/hub`. #194's `Handoff` concern (including the PKCE challenge and the stale-hand-off clearing) moves into the shared path so both routes carry it.
6. **Links keyed by issuer.** `single_sign_on_records` gains `issuer` (a canonical origin), unique on `[issuer, external_id]` and `[issuer, user_id]`. `User` gets `has_many :single_sign_on_records`, and the takeover guard is scoped per issuer. A Sabha Cloud bootstrap link and later shortcut sign-ins share the `https://sabha.co` issuer, so they're one link. The column stays **nullable**: `single_sign_on_records` exists in every tenant database, and `SAAS=true bin/rails db:migrate:primary` migrates all of them, including installs where `SSO_PROVIDER_URL` isn't set, so a NOT NULL constraint would fail those migrations. The migration fills `issuer` from the origin of `SSO_PROVIDER_URL` where it's set; blank rows are stamped by the first custom-SSO callback that presents their `external_id`. SQLite allows multiple NULLs in a unique index, so the new indexes hold. Discard the `db/schema.rb` and schema-cache changes the SaaS migrate command re-dumps from a drifted tenant database.
7. **Link from the profile only.** At login, an unlinked shortcut identity either creates an account (invite or auto-provision) or stops with "sign in the usual way, then connect sabha.co from your profile". Connecting needs a password or email-code check from the last 10 minutes. An unverified sabha.co email never links or creates an account.
8. **sabha.co finds the caller from `return_sso_url`.** It reads the host from the not-yet-verified payload, looks up a `RemoteWorkspace` whose `pairing_status` is `active`, and verifies with that one secret. Unknown, pending and revoked origins are rejected before any HMAC work; a revoked one gets an explanatory page instead of a bare 403. Env clients keep working through the same lookup, including wildcards, the exact-claim guard, and their return paths.
9. **Prove the origin before trusting the secret.** Starting a pairing creates a `RemoteWorkspacePairing` with its own secret; it doesn't touch the shared `RemoteWorkspace` row. Verify fetches the manifest and checks `hub_proof = HMAC-SHA256(secret, "sabha-hub-pairing:" + origin)`; the winning request's secret and requester move onto the `RemoteWorkspace` (`pairing_status: active`, `paired_by`) and the request is deleted. A verified request **replaces** any existing pairing: control of the server is the proof, so this is also how rotation works and how a community recovers when the original pairer is gone. Any number of requests can be pending for one origin, so a squatter can't block the real admin, and requests expire after 24 hours. Only unverified secrets are ever pending; sabha.co signs and verifies with the active secret alone. Pairing refuses hosts an env client claims.
10. **Secret encrypted on sabha.co, shown once.** Uses ActiveRecord encryption, with keys as new deploy config (`ACTIVE_RECORD_ENCRYPTION_*` in `config/deploy.multitenant.yml`). Rotating is a new pairing request. Between the community restarting with the new secret and Verify, the two sides disagree and the shortcut fails with the "not connected" page; the settings screen says to click Verify straight after restarting. Accepting pending secrets to close that gap would let a squatter's secret sign requests, so we don't.
11. **Consent before identity, recorded at the right point.** The consent timestamp is written after the person approves and before `Saas::SingleSignOnsController#show` redirects back to the community. #194 gives that action no desktop branch, so there's one redirect to cover. Env clients skip consent and get no list entry.
12. **One order across two sources.** The selector renders workspaces and list entries through the same partial with an `external` variant. Reorder sends typed ids (`workspace:<external_id>`, `remote:<id>`) and one action writes positions to both tables from one sequence.
13. **The desktop app gets the list through the destination catalog.** `api/destinations/show.json.jbuilder` in SaaS mode adds `remote_peers` after the workspace peers: origin, name, sabha.co's logo endpoint URL, and whether the shortcut is on. A top-level `order` lists every peer id, workspaces and communities together, in the person's selector order, so a client can rebuild the mixed order. They read only untenanted rows, so building the catalog never opens a tenant connection pool. They're a separate key so a client that only understands workspace peers keeps working within protocol major 1. For the shortcut, the app opens the community's `/session/hub` in the system browser with #194's hand-off parameters, including the PKCE challenge; the community issues the session claim and the app redeems it with its verifier. The app holds a cookie session per community partition; sabha.co never sees it.
14. **Limits and upkeep.** Adding is rate-limited per identity with `rate_limit ..., by: -> { current_global_identity.id }` (its counters live in the shared, untenanted `Rails.cache`, which is what we want; the default key is the IP, which would lump people behind one address together) and capped at 100 memberships. A daily job in `config/recurring.yml` refreshes each `RemoteWorkspace` that has at least one membership or an active pairing, sets `unreachable_since` after repeated failures and clears it on success, and deletes rows with neither. Active Job records the tenant it was enqueued in, so the recurring job runs with no tenant and touches only `UntenantedRecord` models; the logo fetch after an add is enqueued from an untenanted route.
15. **Untenanted models and account deletion.** `RemoteWorkspace`, `RemoteWorkspaceMembership` and `RemoteWorkspacePairing` inherit from `UntenantedRecord`, with migrations in `saas/db/untenanted_migrate/`. Deleting a `GlobalIdentity` destroys its memberships and pending pairings and nullifies `paired_by` on workspaces it paired; the pairing itself stays active until the community disconnects or re-pairs.
16. **Untenanted URLs from tenanted pages.** The selector renders inside workspace pages (`/1000121/…`), and Rails path helpers carry the request's `script_name`, so `remote_workspaces_path` there would come out as `/1000121/remote_workspaces`. `Sabha::Saas::PathRewriter` would then resolve a tenant and workspace-membership checks would run. Every sabha.co-level link and form (add, hide, reorder, logo, Your communities, consent) passes `script_name: ""`, the mirror image of the selector's existing `root_path(script_name: slug)` for workspace links. If the selector later updates live, it streams on the `GlobalIdentity`, never a bare symbol.
17. **Identity is the key, never the name.** A sabha.co workspace is identified by `Workspace.external_id`; a self-hosted community by its canonical origin, unique on `remote_workspaces.origin` (a self-hosted install has exactly one community, so one origin is one community). Memberships are unique per identity and workspace in their own tables; the selector's typed ids (`workspace:<external_id>`, `remote:<id>`) and the catalog's separate `peers` / `remote_peers` keys keep the two id spaces apart, and the desktop app keys sessions by origin (every tenanted workspace shares sabha.co's).
18. **Origin normalisation, one function used everywhere** (add, prompt link, pairing, platform API, provider lookup): `https` only; lowercase host; IDN hosts converted to punycode; trailing dot and default port dropped; path, query and fragment discarded. `www.` and the apex stay distinct because redirects are never followed. Anything whose normalised host is sabha.co's own `Branding.app_host` is refused, except `/<workspace id>` paths, which are routed to that workspace's join flow.
19. **Aliases are surfaced, not merged.** The manifest's `community.url` is a hint, not proof: any server can claim any address, and an unpaired one can prove nothing. When it differs from the pasted origin, sabha.co shows both and lets the person choose; it ignores hints that aren't public `https` origins (such as an unset `APP_HOST` reporting `localhost`). Pairing and the shortcut stay bound to the exact origin that published `hub_proof`.

20. **Mobile on Hotwire Native.** Hotwire Native renders each community's server HTML, so no JSON API is needed for screens; the web app already has a start (`@hotwired/hotwire-native-bridge` pinned, a `bridge--button` component, the `native` stylesheet behind `hotwire_native_app?`, and `GET /configurations/ios_v1`). What the multi-community app adds:
    - **One `Navigator` per community**, and a custom route decision handler that treats every origin in the person's list as in-app; anything else still opens externally.
    - **Path configuration from sabha.co.** Hotwire Native loads one configuration per app, not per server. sabha.co serves `ios_v1` and a new `android_v1`; rules stay generic because self-hosted communities run older versions. A community's own `/configurations/ios_v1` is no longer what the app reads.
    - **Sign-in hand-off** via the system browser with #194's parameters. The app redeems the claim with a native `POST /api/session_claim` (so it can send `Sabha-Protocol-Major` and the verifier), then copies the returned session cookie into `WKHTTPCookieStore` / `CookieManager` for that origin.
    - **Detection stays on the user agent** (`hotwire_native_app?`, set through `Hotwire.config.applicationUserAgentPrefix`); web view page loads can't reliably carry a custom header.
    - **App Store 4.2**: native push (once the relay exists), badges, the native switcher and share handling keep the app above "minimum functionality".
    - **Fallback**: Flutter is the backup choice for mobile. If it's ever needed, the list, catalog and consent carry over unchanged; only per-community sign-in changes, because a Flutter app would hold API tokens rather than web view cookies.
## Data model

**sabha.co (untenanted Postgres)**

```
remote_workspaces
  id, origin (canonical https origin, unique), name, refreshed_at,
  unreachable_since (nullable), protocol_major,
  logo_data (binary, ≤ 64 KB), logo_content_type,   -- not Active Storage: blobs are tenanted
  hub_secret (encrypted, nullable),
  pairing_status (none | active | revoked, default none),
  paired_via (self_serve | sabha_cloud, nullable),
  paired_by_global_identity_id (fk, nullable), paired_at, last_signed_in_at,
  created_at, updated_at

remote_workspace_pairings            -- pending requests only
  id, remote_workspace_id (fk), global_identity_id (fk),
  secret (encrypted), expires_at, created_at

remote_workspace_memberships
  id, global_identity_id (fk), remote_workspace_id (fk),
  source (added | prompt | shortcut | sabha_cloud),
  position (integer), hidden (boolean, default false),
  consented_at (nullable), last_opened_at, created_at, updated_at
  unique [global_identity_id, remote_workspace_id]
```

**Each community (tenant SQLite)**

```
single_sign_on_records
  + issuer (string, nullable; filled from SSO_PROVIDER_URL or on first use)
  unique [issuer, external_id]; unique [issuer, user_id]
```

## Interfaces

**Community (instance)**
- Manifest (`GET /api/manifest`): adds `community.name`, `community.logo_url`, `community.url` (canonical, from `APP_HOST`), and `hub_proof` when paired.
- "Add to your sabha.co list" link after sign-in, hidden when the admin turns it off, for users with a sabha.co link, or after the member dismisses it (`resource :hub_list_prompt, only: :destroy`, stored in `User#preferences`).
- `GET /session/hub`, `GET /session/hub/callback`: the shortcut handshake and signed return.
- Profile → Sign-in methods: `resource :hub_link, only: %i[ new create destroy ]`. Creating needs fresh auth; destroying is refused for the last method.
- Env: `SABHA_HUB_SECRET`, `SABHA_HUB_AUTO_PROVISION`, plus a setting to hide the list prompt. The hub is always `https://sabha.co` (`Sabha::HUB_URL`), not configurable.
- All community-side routes above are declared `unless Sabha.saas?`.

**sabha.co (hub)**
- `resources :remote_workspaces, only: %i[ new create ]`: add by address; `new` takes `?origin=` from the prompt and creates the workspace row if it's the first person to list it.
- `resources :remote_workspace_memberships, only: %i[ update destroy ]`: hide, position, remove.
- `resources :remote_workspaces do resource :logo, only: :show end`: serves the stored logo bytes, untenanted.
- All of these are untenanted routes, reached with `script_name: ""` from workspace pages.
- Settings → Your communities: the list, per-entry remove and disconnect, clear-all.
- Settings → Connected communities (admins): `resources :remote_workspace_pairings, only: %i[ new create update ]` for pair and Verify, plus rotate and disconnect on the paired workspace.
- The consent screen in the provider flow.
- `POST /api/platform/remote_workspaces`: control-plane create (bearer platform token). Creates an already-active pairing, returns origin and secret, and adds the owner's membership when `owner_email` is given.
- Desktop catalog: list entries as external peers.

## Verification

- Community: `bin/rails test test/controllers/sso/ test/controllers/sessions_controller_test.rb test/controllers/users_controller_test.rb test/models/single_sign_on_record_test.rb test/models/first_run_test.rb test/controllers/api/ test/controllers/sso/handoff_test.rb`, plus new tests for the migration on a database with blank `issuer` rows, the shortcut (including the PKCE hand-off through `/session/hub`), profile linking, `hub_proof`, and the list prompt (shown, dismissed, hidden for linked users, hidden when the admin turns it off).
- sabha.co: `SAAS=true AUTH_METHOD=otp bin/rails test saas/test/`, plus new tests for origin normalisation (case, port, trailing dot, IDN, path stripped), refusing sabha.co's own host and routing `sabha.co/<id>` to the join flow, the alias hint (shown, ignored when not public https), adding by address (guarded probe failures, communities from before #194, a different protocol major, rate limit and 100-entry cap), the prompt flow, hide, remove and reorder across sources, logo copying, the refresh job (unreachable marking, cleanup of unlisted rows), pairing, Verify and replacement by a newer verified pairing, provider lookup (records, env, wildcard, revoked), consent, `remote_peers` in the catalog, account deletion, links from a workspace page resolving without a tenant prefix, the logo endpoint serving stored bytes, and the recurring job running with no tenant.
- Manual:
  - Add an unpaired local community by address and through its prompt; confirm the link opens its own login.
  - Pair it; confirm a pending pairing squatted by someone else doesn't block the real one; rotate and confirm the gap closes at Verify.
  - Stop the community; confirm the entry turns unreachable after the refresh job and recovers when it's back.
  - In the desktop app, open a shortcut community; confirm the system-browser hand-off lands in the app signed in, and that a claim redeemed without the verifier is refused.
  - In the mobile app, switch between a sabha.co workspace and two self-hosted communities; confirm listed origins stay in-app, an unlisted link opens externally, and the shortcut's claim ends with the web view signed in.
  - Sign in with the shortcut; see consent once; confirm the entry gains the shortcut.
  - Confirm an email match without a link stops with the profile message.
  - Disconnect as admin; confirm the entry falls back to plain.
