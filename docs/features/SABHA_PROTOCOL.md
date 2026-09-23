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

### Destinations

Authenticated catalog after sign-in.

- Self-hosted mode returns exactly one branded peer with `workspace_url` and `cable_url` (`/api/cable` on the origin).
- SaaS mode returns the person's active workspaces in their selector order. Each peer includes a tenant-scoped `cable_url` such as `/api/cable?wid=1000001`.

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

A handshake without these parameters clears any earlier pending handoff. After successful SSO, Sabha redirects to `sabha://session-claim?token=…&origin=…&nonce=…`. The app redeems it via `POST /api/session_claim` with `token`, `nonce`, `origin` and `code_verifier`, and the response carries `return_path`.

Password, email-code, and ordinary browser SSO flows without hand-off parameters are unchanged.

## App detection

Sabha's apps send a `Sabha-Client` header naming themselves: `desktop` today, `mobile` later. The desktop app sends it on every request from a destination session, and `platform.desktop_app?` reads it. It is a layout hint, not an authentication signal. Sabha suppresses the in-page SaaS workspace rail and sidebar WebPush enrollment UI for those requests while preserving the ordinary Hotwire interface.

# Desktop app

## Notifications and badges

The desktop app subscribes to `DesktopChannel`. On subscribe it receives a badge snapshot (`type: "badge"`); after that it gets one `type: "notification"` event per eligible message, following the same eligibility rules as web push, plus a fresh badge whenever the count changes. Old notifications are never replayed. Delivery is off unless `DESKTOP_NOTIFICATIONS_ENABLED=true`.

## Related docs

- [Deployment](../DEPLOYMENT.md) — protocol availability on self-hosted installs
- [Multi-tenant deployment](../multi-tenant/DEPLOYMENT.md) — SaaS destination catalog
