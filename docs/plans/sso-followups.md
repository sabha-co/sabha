---
title: SSO Self-Hosted Followups
type: feat
status: active
date: 2026-05-25
---

# SSO Self-Hosted Followups

## Summary

Findings from a live end-to-end SSO test on a fresh self-hosted Sabha box with Discourse as the DiscourseConnect provider. Core SSO is working — payload signing, callback handling, user provisioning, and SSO record linking all behave as `docs/SSO.md` describes. Three product gaps surfaced that are not specific to Discourse and affect every SSO consumer setup. Each is small in scope but materially shapes the first impression a community gets.

---

## Test Context

- Discourse acting as DiscourseConnect provider at `discourse.example.com`.
- Sabha self-hosted at `chat.example.com`, `AUTH_METHOD=sso`, both `SSO_OVERRIDES_NAME` and `SSO_OVERRIDES_AVATAR` enabled.
- First admin signed in via SSO and provisioned as User 1 (`administrator`).
- Second user signed up in Discourse, was activated, then logged into Sabha via SSO and provisioned as User 2 (`member`).

What worked: redirect chain, signature verification, nonce handling, `SingleSignOnRecord` link, repeated logins refreshing `updated_at`, branding env flowing through to Sabha.

What surfaced: the three issues below.

---

## Finding 1 — First-Run Flow Should Not Run Under SSO

### Observed

When the very first SSO-authenticated user lands in Sabha, no `Account` exists yet, so `Current.account&.sso_auth?` is `nil` and `Authentication#request_authentication` falls through to `new_session_url`. `SessionsController#ensure_user_exists` (`app/controllers/sessions_controller.rb:56`) then sees `User.none?` and redirects to `first_run_url`. `FirstRun.create!` (`app/models/first_run.rb:33`) is built around manual form input — admin email, name, password — and is rendered through a setup form even though SSO already carries `external_id`, `email`, and (optionally) `name`.

In the test, the first user filled in account name and personal name by hand even though their identity was already authoritative from the provider. That data should never have been asked for.

### Why It Matters

- The setup form prompts for fields (email, password) that have no meaning in SSO mode and conflict with the identity the provider just attested to.
- Account name defaults are ignored — the admin is forced to pick a workspace name on their first login, when `APP_NAME` already exists as a branding signal.
- It is the first interaction a community admin has with Sabha after switching to SSO. Asking them to re-type things their parent app already knows reads as broken.

### Proposed Direction

When `Current.account&.sso_auth?` (or `Sabha::AUTH_METHOD == "sso"` at boot, before any Account exists), the first SSO callback should auto-bootstrap:

- Create `Account` with `name: Branding.app_name`.
- Create the admin `User` from the SSO payload (`email`, `name`, `external_id`), role `administrator`.
- Create `SingleSignOnRecord` linking them.
- Create the default `Rooms::Open(name: "General", auto_join: true)` and grant the admin membership.
- Open the session and redirect to root, skipping the first-run form entirely.

This mirrors what `FirstRun.auto_bootstrap!` already does for Sabha Cloud's headless `AUTO_BOOTSTRAP` path — extend the auto-bootstrap branch to recognize SSO mode and use the SSO payload as the source of truth.

### Scope

Single Rails change. New `FirstRun.auto_bootstrap_from_sso!(payload)` called from `Sso::CallbacksController#sign_in_via_sso` when `Account.none?`, before `User.sign_in_with_sso!` runs. Must explicitly set `role: :administrator` on the bootstrap user — `SingleSignOnRecord.provision_user!` defaults new users to `member`, so without an explicit assignment a fresh SSO install ends up with zero admins. Must also preserve the existing `pending_join_code` redemption path so invite-link flows continue to work. Form view and `first_runs#new` remain for non-SSO single-admin installs.

---

## Finding 2 — Sabha-Initiated Logout Does Nothing Visible Under SSO

### Observed

`SessionsController#destroy` correctly nukes the local Sabha session and redirects to `root_url`. But `Authentication#request_authentication` in `app/controllers/concerns/authentication.rb:86` immediately redirects any unauthenticated page to `sso_handshake_url` when the account is SSO-backed. The browser still has a valid provider cookie, so the provider silently signs a payload and bounces back, and Sabha opens a fresh session before the logged-out state ever paints.

End result: clicking "log out" in Sabha looks like nothing happened.

### Why It Matters

- "Log out" is a fundamental control. When it visibly fails, users assume the app is broken or that they cannot leave their session on a shared device.
- The current SSO contract is "provider owns identity, consumer trusts it forever". That is correct for re-auth, but a consumer still needs to offer a local-only sign-out so users can leave Sabha without having to also log out of the parent app.
- The only workaround today is incognito / separate browser profile. That is not a real answer for community admins.

### Proposed Direction

Add a public `signed_out` surface that is exempt from the SSO auto-redirect:

- New route, e.g. `GET /session/signed_out`, controller action with `allow_unauthenticated_access` and *no* SSO before-action.
- The view says "You're signed out of Sabha" and offers a single "Sign in" button that hits `/session/sso`.
- `SessionsController#destroy` redirects to that page instead of `root_url`.
- Visiting any other path while logged out still goes through SSO (the existing behavior — that is the "I want in" intent).

This stays inside Sabha's responsibilities — no SLO contract with the provider, no provider-side coordination, no breaking change to `docs/SSO.md`. It just gives the local logout a place to land that does not get auto-re-authenticated.

### Scope

New route, new controller action, new view, one-line change in `SessionsController#destroy`. No model changes.

### Optional Stretch

Once we have a `signed_out` page, layer in optional federated logout for operators who want it: a config flag that makes the "Sign in" button on the signed-out page also link to the provider's logout endpoint (Discourse exposes one). Off by default — only operators who want both sessions to drop know to enable it.

---

## Finding 3 — New-User Empty State Should Acknowledge the Workspace

### Observed

When a freshly provisioned user lands in Sabha with no room memberships, they see a panel titled "Welcome to {APP_NAME}" (the title already uses `Branding.contextual_app_name` at `app/views/welcome/show.html.erb:15`) followed by a generic body — "You haven't joined any rooms yet. Join or create a room to start chatting with your team." — and a "Create a Room" button.

The title is branded, but the body copy and CTA aren't, and nothing on the screen acknowledges that the user was just provisioned via SSO. The page reads as a generic empty state rather than confirmation that they've landed in the right place.

### Why It Matters

- New users arrive via SSO from the parent app where they already have an identity. The first screen should confirm: "You're in. You belong here." A branded title alone doesn't carry that — the body copy currently doesn't mention the workspace or how they got there.
- `APP_NAME`, `APP_DESCRIPTION`, `APP_SHORT_NAME` are operator-set for branding throughout the app. The empty-state body and CTA don't use them.
- Combined with Finding 1 (the first-run flow running when it shouldn't) and the separate `auto_join` bug in `FirstRun.create!`, the SSO new-user experience today is: pushed through a setup form, then dropped into a half-branded empty workspace. Each piece reinforces the impression that the user landed somewhere generic.

### Proposed Direction

Two small copy changes plus one behavior change:

1. Empty-state body and the `Create a Room` panel should reference `Branding.contextual_app_name` so the whole screen matches the title. (The title itself is already correct.)
2. After SSO-driven provisioning, render a one-time toast or banner on first landing: "Welcome to {APP_NAME}, {user.name}. You're signed in via {provider}." Provider name is operator-configurable, defaults to "your account".
3. Ensure the default `General` room created at first-run uses `auto_join: true` (separate one-line bug — see "Related Fix" below). Once that ships, most new SSO users land directly in `General` and the empty state becomes a much rarer screen.

### Scope

View copy changes only for items 1 and 2. Item 3 is the existing one-line bug.

---

## Related Fix — `auto_join` Bug in First-Run

`app/models/first_run.rb:35` creates the default room without `auto_join: true`:

```ruby
room = Rooms::Open.new(name: FIRST_ROOM_NAME)
```

Compare to `db/seeds/self_hosted.rb:23` and `lib/tasks/generate_workspace.rake:179`, both of which correctly set `auto_join: true`. The production first-run path is the outlier. Result: every fresh self-hosted install ships with a default room that does not auto-join new signups — regardless of auth method.

One-line fix:

```ruby
room = Rooms::Open.new(name: FIRST_ROOM_NAME, auto_join: true)
```

Worth shipping as its own small PR independent of the followups above.

---

## Suggested Sequence

1. Land the `auto_join` one-line fix first. Removes the most visible symptom of Finding 3 for non-SSO installs.
2. Land the `signed_out` page from Finding 2. Self-contained, low risk, immediately useful.
3. Land the SSO auto-bootstrap from Finding 1. Removes the first-run form for SSO installs and makes Finding 3's "welcome by app name" copy meaningful from the very first interaction.
4. Layer in the empty-state branding copy from Finding 3 alongside or after Finding 1.
