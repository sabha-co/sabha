# Load testing & capacity

How a self-hosted Sabha instance behaves under concurrent WebSocket load, how to
reproduce the test, and what the numbers mean for sizing a deployment.

The harness lives in [`test/performance/`](../../test/performance/) (a [k6](https://k6.io)
script plus fixtures). See [`test/performance/README.md`](../../test/performance/README.md)
for the script-level details; this doc covers methodology, results, and recommendations.

---

## TL;DR

On a **1 vCPU / 2 GB** VPS running Sabha v1.10.0:

| WebSocket layer | Comfortable | Practical ceiling | Failure mode |
|---|---|---|---|
| **In-process ActionCable** (default) | ~600 concurrent | **~1,000 concurrent** | Hard crash + restart at ~1,500 |
| **AnyCable** (anycable-go) | ~2,000 concurrent | **~3,000+ concurrent** | Graceful — slow connect, no crash |

- **The bottleneck is always the single CPU core, never RAM** (memory stayed under ~950 MB of 1.9 GB at every level).
- With **in-process ActionCable**, WebSockets share the Ruby core with the web app; holding ~1,000 idle connections already costs ~80% CPU just for keepalive.
- **AnyCable** moves connection-holding into a Go process (~25% CPU / ~85 MB to hold 3,400 connections), roughly **2–3× the ceiling on the same box** with no crashes. The bottleneck shifts to Rails RPC throughput for *connection establishment*.
- A **connection storm** (many clients connecting at once, e.g. after a deploy/restart) is a sharper limit than steady-state concurrency: ~167 conns/sec crashed the in-process setup even at 500 total.

---

## Test setup

- **Target:** 1 vCPU / 2 GB / Ubuntu 24.04 VPS (DigitalOcean), the smallest spec in
  [DEPLOYMENT.md](../DEPLOYMENT.md)'s requirements table.
- **Image:** `ghcr.io/sabha-co/sabha:1.10.0`, run in `RAILS_ENV=performance`.
- **Generator:** k6 on a separate machine (laptop) over the public internet, so the
  load generator never steals CPU from the target.
- **Seed:** `config/environments/performance.rb` auto-seeds **10,000 users + sessions,
  201 rooms, ~11,000 memberships** on first boot. Room 1 contains *every* user.
- **Auth:** the test authenticates as seeded users with pre-signed `session_token`
  cookies (`SECRET_KEY_BASE=dummy`); WebSocket origin checks are disabled in the
  performance env.

Each virtual user opens a WebSocket and subscribes to the same channels a real
room page does: `PresenceChannel`, `UserUnreadRoomsChannel`, `HeartbeatChannel`,
and three signed `Turbo::StreamsChannel` streams.

### Reproducing it

```bash
# On the target VPS — in-process ActionCable (default self-host)
docker compose up -d            # see compose snippets below

# On the generator
ruby test/performance/create_dummy_cookies.rb > test/performance/cookies.txt
cd test/performance
HOST=<target-ip> PORT=3000 USERS=1000 RATE=20 HOLD=50 DURATION=80s k6 run chatter.js
```

Two non-obvious things are required to run the image in the performance env (both
because `performance` inherits `production` but isn't `Rails.env.production?`):

1. **Prepare the DB yourself.** `bin/boot` only runs `db:prepare` when
   `RAILS_ENV=production`. Use `command: sh -c "./bin/rails db:prepare && exec ./bin/boot"`.
2. **`SKIP_THRUSTER=1`** to expose Puma directly on `:3000` (no TLS/Thruster in front).

> The in-process ActionCable compose (a no-AnyCable baseline) is no longer
> available: AnyCable is required, and `ANYCABLE_ENABLED=false` now aborts boot.
> Use the AnyCable compose below.

<details>
<summary>AnyCable compose</summary>

```yaml
services:
  web:
    image: ghcr.io/sabha-co/sabha:1.10.0
    command: sh -c "./bin/rails db:prepare && exec ./bin/boot"
    environment:
      RAILS_ENV: performance
      SECRET_KEY_BASE: dummy
      SKIP_THRUSTER: "1"
      APP_HOST: <target-ip>
    ports: ["3000:3000"]
    volumes: ["sabha_storage:/rails/storage"]
  anycable:
    image: anycable/anycable-go:1.6
    command: >
      --host=0.0.0.0 --port=8080 --http_broadcast_port=8080
      --rpc_host=http://web:3000/_anycable --broadcast_adapter=http
      --secret=test-secret --streams_whisper
    ports: ["8080:8080"]
    depends_on: [web]
volumes: { sabha_storage: }
```

With AnyCable, k6 connects WS to `:8080` but posts HTTP to `:3000`
(`WS_PORT=8080 PORT=3000`).
</details>

---

## Results — in-process ActionCable (default)

Connections established *gently* (~15–20/sec) and held open:

| Concurrent | WS errors | Handshake (p95) | Steady CPU | Verdict |
|---:|---:|---:|---:|---|
| 200 | 0 | ~0.3 s | ~5% | Trivial |
| 600 | 0 | 0.28 s | ~45% | Healthy |
| 1,000 | 0 | 0.61 s | **~80%** (peaks 98%) | At the edge |
| 1,500 | **674** | **22.7 s** | 100% | **Crash + restart** |

- **Holding connections isn't free.** ActionCable keepalive pings + presence
  refreshes across N sockets run on the single Ruby core: ~1,000 idle connections
  already consume ~80% CPU, leaving no headroom for messages or new connections.
- **At ~1,500 the process died and was restarted** by Docker (`restart: unless-stopped`)
  — handshakes blew out to 20–30 s and ~674 connections errored. The box has **no
  swap**, so CPU saturation tips into an abrupt OOM-style process kill rather than
  graceful slowdown.

### Connection storms are a separate, sharper limit

The same 1,000 connections that held fine at 20/sec **crashed the box when
established at 167/sec** (1,000+ errors, 10 s handshakes). Real users don't connect
that fast — but they do all reconnect at once after a deploy or restart. A 1 vCPU
in-process self-host tolerates roughly **≤ 25 new connections/sec**.

---

## Results — AnyCable

Same box, WebSockets offloaded to anycable-go:

| Concurrent | Handshake (median / p95) | web CPU | anycable-go CPU / RAM | Verdict |
|---:|---|---:|---|---|
| 2,000 | 19 ms / 21 s | ~65% | **~20% / ~90 MB** | Clean, no crash |
| ~3,400 | 5 s / 30 s (timeout) | ~65% | **~25% / ~85 MB** | Held, no crash; establishment-bound |

- **anycable-go holds thousands of connections for almost nothing** — ~85 MB of RAM
  and ~25% CPU at 3,400 connections. Connection-holding is no longer the limit.
- **No crashes** at any level (vs ActionCable crashing at 1,500).
- The new bottleneck is **Rails RPC for connection *establishment***: every connect +
  subscribe is an HTTP RPC call back to Rails, and Puma's default 5 threads (plus
  SQLite write contention on presence/subscribe) cap establishment throughput. Note
  web CPU was only ~65% even when handshakes timed out — it's thread/IO-bound on RPC,
  not CPU-bound. Raising `RAILS_MAX_THREADS` would push the establishment ceiling higher.

### CPU split tells the story

At ~2,000 concurrent: **anycable-go ~20% CPU** (holding sockets) vs **web ~65%**
(RPC auth/subscribe + jobs). AnyCable did exactly what it's for — it took persistent
connections out of the Ruby process.

---

## Message throughput (both modes)

Posting a message is dominated by **room membership size**, not the cable layer.
Room 1 in the seed has all 10,000 users, so each post fans out unread/notification
work to every member: it **pegs the Ruby core at 100% for ~2.5–4 s per message**.
A normal 50–200-member room is far cheaper. This is a separate scaling axis from
connection count — large rooms are expensive to post into regardless of ActionCable
vs AnyCable.

---

## Gotchas discovered

These tripped up the test and are worth knowing (or fixing):

- **`performance` cable.yml now uses `any_cable` directly.** Earlier this block
  resolved the adapter from `ENV.fetch("CABLE_ADAPTER", "redis")`, so forgetting
  `CABLE_ADAPTER=any_cable` left ActionCable on the **redis** adapter and Turbo
  broadcasts went to Redis (which anycable-go never reads) — connections worked but
  **no messages were delivered**. Since AnyCable became required, every app
  environment (including `performance`) uses `any_cable` unconditionally, so
  `CABLE_ADAPTER` and `ANYCABLE_ENABLED` are no longer read.
- **anycable-go must bind `--host=0.0.0.0`** in Docker, or it listens on localhost
  inside the container and docker-proxy can't reach it.
- **Disabling broadcast batching floods anycable-go.** With `broadcast_batching: true`
  (the default), per-member broadcasts for a large room are aggregated into one POST;
  with it off, each becomes a separate HTTP POST and delivery degrades under load.

The load-test fixtures themselves were also stale and were corrected: the signed
Turbo stream names referenced the pre-fork `gid://campfire/...` app name, and the
dummy cookie generator derived keys with SHA1 instead of the SHA256 that
`load_defaults 8.2` uses (so no cookie would authenticate). See
[`test/performance/README.md`](../../test/performance/README.md).

---

## Recommendations

For a self-hosted Sabha instance:

1. **Enable AnyCable once you expect more than a few hundred concurrent users.** On a
   1 vCPU box it roughly tripled the connection ceiling and removed the crash cliff.
   The Kamal deployment ([DEPLOYMENT.md](../DEPLOYMENT.md)) wires this up by default.
2. **Add 1–2 GB of swap.** With none, CPU saturation kills and restarts the app
   process instead of degrading gracefully.
3. **Size for reconnect storms, not just steady state.** The worst load is everyone
   reconnecting after a restart. AnyCable's `restore_from_cache` helps; staggering
   client reconnects helps more.
4. **With AnyCable, raise `RAILS_MAX_THREADS`** (and watch SQLite contention) to lift
   the RPC establishment ceiling — that, not connection-holding, becomes the limit.
5. **Watch room sizes.** Posting into rooms with thousands of members is CPU-heavy
   regardless of the cable layer (per-member unread fan-out).

### Rough sizing guide

| Concurrent users | Suggested setup |
|---|---|
| < 300 | 1 vCPU / 2 GB, in-process ActionCable |
| 300–1,000 | 2 vCPU / 4 GB, in-process ActionCable (or AnyCable) |
| 1,000–5,000 | AnyCable, 2–4 vCPU / 4–8 GB, tuned Puma threads |
| 5,000+ | AnyCable on dedicated nodes; revisit SQLite vs scaling story |

*Numbers measured on Sabha v1.10.0, single 1 vCPU / 2 GB VPS, June 2026. Treat as
order-of-magnitude guidance, not guarantees — re-measure for your own workload.*
