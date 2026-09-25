# Sabha protocol

A small, versioned contract that lets clients discover a Sabha server, find where to sign in, and list the destinations a signed-in person can open. Its readers are the Sabha desktop app, the mobile app, and sabha.co itself when someone adds a community to their list. On top of it, the desktop app gets a system-browser sign-in hand-off, a notification channel, and a layout hint.

## Protocol major 1

Every request to these endpoints sends the `Sabha-Protocol-Major` header. Major version `1` is the only supported version today. Unsupported majors receive HTTP 415 with `supported_major`, and each client shows its own upgrade message.

## Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/api/manifest` | None | Product identity and server-owned sign-in entry |
| GET | `/api/destinations` | Session | Ordered destinations and cable-discovery paths |
| POST | `/api/session_claim` | None | Redeem a one-time SSO session claim (self-hosted only) |

### Manifest

Unauthenticated probe used when a member adds a server origin. Returns protocol major, product name, a sign-in path, and the catalog path. Never returns member records.

A self-hosted server also returns a `workspace` block, so lists can show the workspace rather than the product:

- `name`: the workspace's name, as set in its account settings.
- `logo_url`: an absolute, versioned URL for the logo, or `null` when none is set.
- `url`: the server's canonical origin, from `APP_HOST`. Treat it as a hint: it can differ from the address a member typed, and an unset `APP_HOST` reports `localhost`.

The block is absent before first run and in SaaS mode, where one origin hosts many workspaces. sabha.co instead returns `multi_tenant: true`, so it can't be added to a list as a workspace. A server paired with sabha.co also returns `hub_proof`, which sabha.co checks while pairing.

### Destinations

Authenticated catalog after sign-in.

- Self-hosted mode returns exactly one branded peer, with id `default`, `workspace_url` and `cable_url` (`/api/cable` on the origin).
- SaaS mode returns the person's whole selector list, which the desktop app draws as its own rail:
  - `peers`: the sabha.co workspaces. Each includes a tenant-scoped `cable_url` such as `/api/cable?wid=1000001`.
  - `self_hosted_peers`: the self-hosted workspaces on the person's list, hidden ones left out. Each has `id` (`remote:<n>`), `origin`, `name`, `logo_url` (served by sabha.co, so fetching it needs the sabha.co session; `null` when none), `unreachable` (sabha.co's last check failed; a hint, not a verdict) and `shortcut` (the server is paired with sabha.co, so "Continue with sabha.co" signs in).
  - `order`: the ids of both lists in the person's selector order, as they would send them to reorder.

  Apps key self-hosted entries by `origin`. The `remote:<n>` id is for ordering and display only: removing a server and adding it back gives it a new id, but it is the same server with the same session. A client that doesn't know `self_hosted_peers` or `order` can ignore them.

A missing or expired session answers `401`. Anything else (a `5xx`, a timeout, a page that isn't JSON) says nothing about the session, so an app keeps what it has and tries again.

# Sabha apps

## Session claims

One-time credentials for system-browser SSO return. Claims store only a SHA256 digest of the bearer token, expire after five minutes, and redeem transactionally once into the initiating origin's session partition. Redeeming requires the PKCE `code_verifier` for the challenge sent at the start of the handoff, so an app that intercepts the `sabha://` link can't use it.

Claims live in `session_claims` and exist in self-hosted mode only. In SaaS mode an app signs in to sabha.co inside the app at the manifest's `sign_in_path`.

## SSO hand-off

When an app opens an external sign-in flow in the system browser, it passes these query parameters on the handshake URL:

- `handoff=1`
- `handoff_nonce` — client-generated nonce, echoed back so the app can match the deep link to its pending sign-in
- `handoff_origin` — initiating server origin URL
- `code_challenge` — PKCE S256 challenge: base64url (no padding) of the SHA256 of a random app-held verifier
- `return_to` — optional in-app path to open after redeem; anything other than a local path falls back to `/`

A handshake without these parameters clears any earlier pending handoff. After successful SSO, Sabha redirects to `sabha://session-claim?token=…&origin=…&nonce=…`.

On a self-hosted server paired with sabha.co, the handshake for "Continue with sabha.co" is `/session/hub`. It takes the same parameters, plus the page's own `join_code` when it came from an invite. The desktop app starts it in the system browser, where the person is already signed in to sabha.co, because the server's view inside the app has no sabha.co session. The app redeems it via `POST /api/session_claim` with `token`, `nonce`, `origin` and `code_verifier`, and the response carries `return_path`.

Password, email-code, and ordinary browser SSO flows without hand-off parameters are unchanged.

## App detection

Sabha's apps send a `Sabha-Client` header naming themselves: `desktop` today, `mobile` later. The desktop app sends it on every request from a destination session, and `platform.desktop_app?` reads it. It is a layout hint, not an authentication signal. Sabha suppresses the in-page SaaS workspace rail and sidebar WebPush enrollment UI for those requests while preserving the ordinary Hotwire interface. The desktop app draws the same list from `/api/destinations` instead, and keeps it visible inside self-hosted workspaces. People reorder it on sabha.co's settings page.

# Desktop app

## Notifications and badges

The desktop app subscribes to `DesktopChannel`. On subscribe it receives a badge snapshot (`type: "badge"`); after that it gets one `type: "notification"` event per eligible message, following the same eligibility rules as web push, plus a fresh badge whenever the count changes. Old notifications are never replayed. Delivery is off unless `DESKTOP_NOTIFICATIONS_ENABLED=true`.

## Related docs

- [Deployment](../DEPLOYMENT.md) — protocol availability on self-hosted installs
- [Multi-tenant deployment](../multi-tenant/DEPLOYMENT.md) — SaaS destination catalog
