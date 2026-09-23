# Sabha desktop protocol

Sabha exposes a versioned desktop compatibility contract so the native Sabha desktop client can discover compatible servers, authenticate through existing Sabha flows, enumerate destination peers, and complete system-browser SSO safely.

## Protocol major 1

All desktop API requests must send the `Sabha-Desktop-Protocol-Major` header. Major version `1` is the only supported version today. Unsupported majors receive HTTP 415 with upgrade guidance.

Desktop layout hooks use the non-authoritative `Sabha-Desktop-Client` request header. Browser requests without that header keep the existing workspace selector and WebPush enrollment UI.

## Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/api/desktop/manifest` | None | Product identity and server-owned sign-in entry |
| GET | `/api/desktop/destinations` | Session | Ordered workspace peers and cable-discovery paths |
| POST | `/api/desktop/session_claim` | None | Redeem a one-time desktop SSO claim (self-hosted only) |

### Manifest

Unauthenticated probe used when a member adds a server origin. Returns protocol major, product name, and a sign-in path. Never returns member records.

### Destinations

Authenticated catalog after sign-in.

- Self-hosted mode returns exactly one branded peer with `workspace_url` and `cable_url` (`/api/cable` on the origin).
- SaaS mode returns ordered active workspace memberships only. Each peer includes a tenant-scoped `cable_url` such as `/api/cable?wid=1000001`.

### Session claims

One-time credentials for system-browser SSO return. Claims store only a SHA256 digest of the bearer token, expire after five minutes, and redeem transactionally once into the initiating origin's session partition. Redeeming requires the PKCE `code_verifier` for the challenge sent at the start of the handoff, so an app that intercepts the `sabha://` link can't use it.

Claims live in `desktop_session_claims` and exist in self-hosted mode only. In SaaS mode the desktop client signs in to sabha.co inside the app at the manifest's `sign_in_path`.

## Desktop SSO handoff

When the desktop client opens an external sign-in flow, pass these query parameters on the handshake URL:

- `desktop_handoff=1`
- `desktop_nonce` — client-generated nonce, echoed back so the client can match the deep link to its pending sign-in
- `desktop_origin` — initiating server origin URL
- `desktop_code_challenge` — PKCE S256 challenge: base64url (no padding) of the SHA256 of a random client-held verifier
- `return_to` — optional in-app path to open after redeem; anything other than a local path falls back to `/`

A handshake without these parameters clears any earlier pending handoff. After successful SSO, Sabha redirects to `sabha://session-claim?token=…&origin=…&nonce=…`. The desktop client redeems it via `POST /api/desktop/session_claim` with `token`, `nonce`, `origin` and `code_verifier`, and the response carries `return_path`.

Password, email-code, and ordinary browser SSO flows without desktop handoff parameters are unchanged.

## Client detection

Send `Sabha-Desktop-Client: 1` on desktop-embedded page loads. Sabha suppresses the in-page SaaS workspace rail and sidebar WebPush enrollment UI for those requests while preserving the ordinary Hotwire interface.

## Related docs

- [Deployment](../DEPLOYMENT.md) — desktop API availability on self-hosted installs
- [Multi-tenant deployment](../multi-tenant/DEPLOYMENT.md) — SaaS destination catalog
