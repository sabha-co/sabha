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
| POST | `/api/desktop/session_claim` | None | Redeem a one-time desktop SSO claim |

### Manifest

Unauthenticated probe used when a member adds a server origin. Returns protocol major, product name, and a sign-in path. Never returns member records.

### Destinations

Authenticated catalog after sign-in.

- Self-hosted mode returns exactly one branded destination for the community with `/api/cable` as the cable-discovery path.
- SaaS mode returns ordered active workspace memberships only. Each peer includes a tenant-scoped cable path such as `/api/cable?wid=1000001`.

### Session claims

One-time credentials for system-browser SSO return. Claims store only a SHA256 digest of the bearer token, expire after five minutes, and redeem transactionally once into the initiating origin's session partition.

Self-hosted claims live in `desktop_session_claims`. SaaS claims live in the untenanted `desktop_global_session_claims` table.

## Desktop SSO handoff

When the desktop client opens an external sign-in flow, pass these query parameters on the handshake URL:

- `desktop_handoff=1`
- `desktop_nonce` — client-generated binding nonce
- `desktop_origin` — initiating server origin URL
- `return_to` — optional in-app return path after redeem

After successful SSO, Sabha redirects to `sabha://session-claim?...` with a one-time token. The desktop client redeems it via `POST /api/desktop/session_claim`.

Password, email-code, and ordinary browser SSO flows without desktop handoff parameters are unchanged.

## Client detection

Send `Sabha-Desktop-Client: 1` on desktop-embedded page loads. Sabha suppresses the in-page SaaS workspace rail and sidebar WebPush enrollment UI for those requests while preserving the ordinary Hotwire interface.

## Related docs

- [Deployment](../DEPLOYMENT.md) — desktop API availability on self-hosted installs
- [Multi-tenant deployment](../multi-tenant/DEPLOYMENT.md) — SaaS untenanted claim storage
