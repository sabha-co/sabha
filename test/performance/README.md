# Performance / load testing

A [k6](https://k6.io) load test (`chatter.js`) that simulates many users idling on
ActionCable WebSockets while one user posts messages, exercising the real-time
broadcast fan-out.

## How it works

Two generated fixtures feed the test, k6 drives two scenarios against the target,
and the loop is closed by measuring whether broadcasts come back:

```
  FIXTURES (generated once)
    create_dummy_cookies.rb ─▶ cookies.txt   10k signed session_token cookies
    signed_stream_names.rb  ─▶ chatter.js    signed Turbo::StreamsChannel names
                                   │
                                   ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  k6  (chatter.js)  — load generator, runs OFF the target box │
  │                                                             │
  │   sockets scenario                 messages scenario        │
  │   open + hold N WebSockets         1 user posts messages    │
  │   (RATE/sec, HELD for HOLDs)       (starts at 30s)          │
  └───────┬─────────────────────────────────────┬───────────────┘
          │ ① ws://HOST:WS_PORT/cable            │ ② POST http://HOST:PORT
          │    Cookie: session_token=<dummy>     │    /rooms/1/messages
          ▼                                      ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  SABHA TARGET   RAILS_ENV=performance, SECRET_KEY_BASE=dummy │
  │                                                             │
  │  WebSocket layer (pick one):                                │
  │    • in-process ActionCable ── Puma :3000 /cable            │
  │    • AnyCable ── anycable-go :8080 ──RPC──▶ Rails /_anycable │
  │                                                             │
  │  ① connect  → verify signed cookie → Session → Current.user │
  │     subscribe→ PresenceChannel, UserUnreadRoomsChannel,     │
  │                HeartbeatChannel, 3× Turbo::StreamsChannel    │
  │                                                             │
  │  ② create Message → broadcast_append_to room, :messages     │
  │                          (stream gid://sabha/...:messages)  │
  └───────────────────────────────┬─────────────────────────────┘
                                  │ ③ fan-out to every subscriber
                                  ▼
   each held socket receives  <turbo-stream action="append">  …
   k6 tallies it as the  `appends_received`  metric  ◀── closes the loop
```

The signed cookies (①) and signed stream names (②/③) only validate when the
target boots with `SECRET_KEY_BASE=dummy` and the GlobalID app name `sabha` —
which is why both fixtures are regenerable (see below). Run the generator on a
**separate machine** from the target, or the two contend for CPU and the numbers
measure contention rather than capacity.

## Preconditions

The test authenticates thousands of fake users against a dedicated environment
seeded with matching data. Three things must line up:

1. **`RAILS_ENV=performance`** — `config/environments/performance.rb` inherits
   production, disables ActionCable origin checking, and (on first boot) seeds
   10k users + sessions, 200 rooms, and memberships. Room 1 has every user as a
   member, which is the room the load test targets.

2. **`SECRET_KEY_BASE=dummy`** — both the session cookies and the signed Turbo
   stream names are generated with this secret. The perf server must boot with
   it, or every connection is rejected and no broadcasts are received.

3. **`cookies.txt`** — k6 reads auth cookies from this file (not checked in).

## Running

```bash
# 1. Generate the session cookies (one signed session_token per seeded user).
ruby create_dummy_cookies.rb > cookies.txt

# 2. Boot the app in the performance env (seeds on first run).
SECRET_KEY_BASE=dummy RAILS_ENV=performance bin/rails server

# 3. Run k6 (Docker reaches the host via host.docker.internal).
#    USERS = concurrent WebSocket connections to open.
docker run --rm -i \
  -e HOST=localhost -e PORT=3000 -e USERS=1000 \
  -v "$PWD:/scripts" -w /scripts grafana/k6 run chatter.js
```

The `sockets` scenario opens WebSocket connections, each subscribing to
`PresenceChannel`, `UserUnreadRoomsChannel`, `HeartbeatChannel`, and the signed
Turbo streams. After 30s the `messages` scenario POSTs messages to room 1;
connected sockets count broadcasts via the `appends_received` metric in the k6
summary.

### Parameters (env vars)

| Var | Default | Meaning |
|-----|---------|---------|
| `HOST` | — | Target host/IP (`localhost` maps to `host.docker.internal`) |
| `PORT` | — | HTTP port for `/rooms` and `/messages` (e.g. `3000`) |
| `WS_PORT` | `PORT` | WebSocket port — `3000` for in-process ActionCable, `8080` for anycable-go |
| `USERS` | `500` | Size of the cookie pool to draw from |
| `RATE` | `USERS/3` | New connections per second (establishment rate) |
| `HOLD` | `50` | Seconds each socket stays open |
| `VUS` | `USERS` | Max concurrent virtual users (caps the plateau) |
| `DURATION` | `60s` | How long the sockets scenario runs |
| `MSG_COUNT` | `100` | Messages the `messages` scenario posts (set `0` to skip) |

Steady-state concurrency is roughly `RATE × HOLD` (capped by `VUS`). To probe
*holding* capacity, establish gently (low `RATE`, high `HOLD`); to probe a
*connection storm*, raise `RATE`. For a capacity ramp, see
[`docs/performance/load-testing.md`](../../docs/performance/load-testing.md).

## Regenerating the signed stream names

`chatter.js` hardcodes signed `Turbo::StreamsChannel` names. They encode
GlobalIDs (`gid://sabha/...`) and are signed with `SECRET_KEY_BASE`, so they
break if either the app name or the secret changes. Regenerate and paste the
output into `chatter.js`:

```bash
ruby signed_stream_names.rb            # defaults: SECRET_KEY_BASE=dummy, GID_APP=sabha
```

Both this and `create_dummy_cookies.rb` reproduce Rails/Turbo signing using the
framework defaults (signed-cookie salt, 1000-iteration SHA256 key generator,
JSON serializer). The Gemfile pins Rails to a GitHub ref, so if those internal
defaults ever change upstream, these generators must be updated to match.

## Differences from Campfire's load-test script

This harness was inherited verbatim from [once-campfire](https://github.com/basecamp/once-campfire)
(`test/performance/`). The seed, the k6 scenarios, and the overall approach are the
same. The differences are fork-drift fixes, capability additions, and a shared
latent bug:

| | once-campfire | Sabha |
|---|---|---|
| **Signed stream names** | `gid://campfire/...` (correct for Campfire) | `gid://sabha/...` — updated for the renamed GlobalID app |
| **Channel name** | `UnreadRoomsChannel` | `UserUnreadRoomsChannel` (renamed in Sabha) |
| **Cookie key digest** | SHA1 `KeyGenerator` | **SHA256** (matches `load_defaults 8.2`) |
| **Parameters** | hardcoded `duration: 60s`, `rate = USERS/3` | `RATE`, `HOLD`, `VUS`, `DURATION`, `MSG_COUNT` — establishment rate decoupled from concurrency |
| **WS vs HTTP port** | single `PORT` | separate `WS_PORT` (so the same script drives ActionCable `:3000` or anycable-go `:8080`) |
| **Delivery measurement** | `console.log` per frame | `appends_received` / `subscriptions_confirmed` metrics |
| **Socket lifecycle** | left open until scenario stop | explicit `HOLD` then clean close |
| **AnyCable path** | none (Campfire has no AnyCable) | added (`WS_PORT=8080`) |

Two of these matter beyond cosmetics:

- **The SHA256 fix is a real correction, and once-campfire still has the bug.** Both
  repos are on `load_defaults 8.2`, which derives keys with SHA256, but the inherited
  `create_dummy_cookies.rb` used the `KeyGenerator` SHA1 default. Under 8.2 those dummy
  cookies never authenticate — so Campfire's committed harness is broken the same way
  Sabha's was, just unnoticed.
- **Decoupling rate from concurrency changed what we could measure.** Campfire's
  `rate = USERS/3` means "500 users" is silently a 167-conn/sec *storm*; you can't tell
  a holding-capacity limit from a connection-storm limit. The `RATE`/`HOLD`/`VUS`
  parameters are what let the benchmark separate "~600 held fine" from "167/sec
  crashed it."

Topology also differs: Campfire's `host.docker.internal` default points at an app on
the **same machine** (k6-in-Docker against localhost) — a co-located smoke test, where
generator and target share CPU. The capacity benchmark in
[`docs/performance/load-testing.md`](../../docs/performance/load-testing.md) runs the
generator on a **separate machine** against a dedicated target, which is required to
measure a real ceiling.
