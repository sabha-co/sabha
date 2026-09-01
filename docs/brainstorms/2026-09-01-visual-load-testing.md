---
title: "Visual load testing for Sabha self-hosted (working name: Loadscope)"
date: 2026-09-01
topic: load-testing
---

# Visual load testing for Sabha self-hosted

## Summary

A standalone tool that drives **real** load at a running Sabha self-hosted instance and renders
a **live X-ray of the server's internal state** while the load ramps — Puma threads, DB
connection-pool contention, GVL wait, AnyCable fan-out — on one timeline against offered load.
Not a simulator (it sends real traffic) and not a generic HTTP benchmarker (it understands Rails
internals). Scope is **Sabha self-hosted only**.

It **operationalizes** the one-time manual measurement in
[`docs/performance/load-testing.md`](../performance/load-testing.md): same harness and target
environment, but a **repeatable, live instrument** instead of a static June-2026 snapshot — you
watch the walls hit in real time and get the verdict automatically, rather than reading CPU off
`top` and eyeballing k6 logs after the fact.

The tool is a separate TypeScript repo that lives **outside** the Sabha codebase. The only code
added to Sabha is a few **Yabeda instrumentation gems** plus enabling the anycable-go metrics
flag — no bespoke probe.

---

## Problem Frame

We can generate load at Sabha today (`bin/load-anycable` + k6) and get two numbers out:
connections/sec and messages/sec. What we cannot see *live* is **why throughput flattens** — which
of the known walls we hit, and at what offered load. The four things that actually take down a
single-node Sabha instance:

1. **SQLite single writer** — every message write serializes; the documented Sabha wall.
2. **Puma thread pool + the GVL** — Ruby threads don't run CPU in parallel, so "more threads"
   past a point adds latency variance, not throughput. No existing tool surfaces this.
3. **DB connection-pool exhaustion** — `pool < threads` produces `ConnectionTimeoutError`
   *before* the DB is busy; generic tools misread this as "slow database."
4. **AnyCable fan-out** — one broadcast to an N-member room is N socket pushes; the presence
   gate and the single anycable-go replica are where it bites.

These are **not hypothetical** — the run in
[`docs/performance/load-testing.md`](../performance/load-testing.md) already hit all four: the
single-core ceiling, the RPC-establishment wall (Puma 5 threads + SQLite subscribe contention,
web CPU stuck at ~65% — i.e. thread/IO-bound, not CPU-bound), reconnect-storm fragility, and
multi-second large-room fan-out. What that run lacked was a **live, correlated read-out** — which
is this tool. Existing tooling (k6 + Grafana + APM) splits the story across three panes you
correlate by hand; the insight here is to put **offered load and Rails-internal state on one
timeline, in Rails vocabulary**, so when goodput flatlines you *see* whether it's the GVL, the
pool, the writer, or the transport.

---

## Key Decisions

- **KD1. Stack is TypeScript, not Rails.** The product is a real-time visualization (Vite +
  React), and the load driver needs concurrency the GVL makes Ruby worst at — using Ruby to
  load-test Ruby means the generator hits the wall before the target. UI + orchestrator + driver
  are TypeScript/Node; raw high-concurrency load can delegate to k6/Go.

- **KD2. External observer, not an embedded engine.** The tool talks to Sabha over
  HTTP/Prometheus and takes a base URL. Keeps the load generator out of the target process (so it
  can't distort what it measures) and keeps the tool a clean separate repo.

- **KD3. Reuse the existing harness; do not rebuild.** Sabha already ships `bin/load-anycable` +
  `test/performance/chatter.js` (k6, 6 subs/user incl. presence) and `script/dev/flood-room` /
  `script/dev/populate` for hot-room setup — the same harness `docs/performance/load-testing.md`
  used. Wrap these. The current script uses **raw `k6/ws`** with hand-coded signed stream names
  and `session_token`-cookie auth (`cookies.txt`, 10k pre-generated). Upgrade path (post-v1):
  rewrite the WS layer on **`xk6-cable`** (`k6/x/cable`, from the AnyCable authors) for synchronous
  `connect → subscribe → perform → receive` scripting instead of hand-rolled JSON — less brittle
  than hardcoded stream names.

- **KD4. Server-side metrics come from the Yabeda ecosystem, not a hand-rolled probe.** This is
  the canonical AnyCable-authors path (see Prior Art). Add `yabeda-anycable` (RPC stats),
  `yabeda-prometheus` (the single `/metrics` endpoint the tool scrapes), plus Yabeda plugins for
  ActiveRecord pool, GVL, and Puma. anycable-go's own Prometheus exporter (one flag) covers
  transport metrics. Net-new Sabha code is a few gems + an initializer.

- **KD5. Bottleneck inference is the point.** A rule layer turns raw taps into a plain-Rails
  verdict that names the exact config knob — not just charts.

---

## Architecture

```
loadscope/                    (standalone Vite + React + Node repo, outside sabha)
  engine/   ramp scheduler, metric time-series store, bottleneck inference
  driver/   wraps Sabha's bin/load-anycable / k6 (ramp connections + message rate)
  taps/     scrape Prometheus /metrics (yabeda: RPC, AR pool, GVL, Puma threads) +
            anycable-go /metrics (transport) + presence API on :8080 (fan-out width)
  ui/       hardcoded Sabha topology, live meters, goodput-vs-offered chart

sabha side (net-new, minimal):
  gems      yabeda-anycable + yabeda-prometheus (+ AR-pool / GVL / Puma plugins) + initializer
  flags     enable anycable-go's Prometheus metrics exporter
```

**Bottleneck inference** turns taps into a verdict that names the knob. The rules are not
invented — they encode published Rails operational heuristics (see Prior Art) *and* the failure
modes already observed in `docs/performance/load-testing.md`, e.g.:
- `pool.stat.waiting > 0 && db_busy low` → "connection pool exhausted, raise `pool`."
- `gvl_wait high && cpu pinned` → "GVL-saturated, more threads won't help."
- `rpc_latency high && web_cpu < 80% && threads all busy` → "establishment thread/IO-bound —
  raise `RAILS_MAX_THREADS` (watch SQLite contention)." (The exact case the results doc hit.)
- `load_avg/nproc ≈ 1.5 && cpu ≈ 50%` → "I/O-bound (SQL) — optimize the query/writer, don't
  scale out" (RoRvsWild's rule).
- `load_avg/nproc ≈ 1.5 && cpu ≈ 99%` → "maxed — add a node or cut CPU work."

The value: these rules today live in a human's head, a blog post, or a one-off results doc; the
tool applies them live against real taps. Capacity baseline uses the standard formula
`total_threads = WEB_CONCURRENCY × RAILS_MAX_THREADS` and the pool-per-thread invariant (the DB
must accept ≥1 connection per thread).

---

## Prior art & where this sits

- **Sabha's own results (`docs/performance/load-testing.md`).** The empirical baseline this tool
  automates: a one-time June-2026 run on a 1 vCPU/2 GB VPS that measured the ceilings (in-process
  ActionCable ~1,000 concurrent; AnyCable ~3,400) and named the bottlenecks (single core, RPC
  establishment, reconnect storms, large-room fan-out). The tool turns that manual snapshot into a
  live, repeatable instrument and adds the metrics that run had to *infer* (GVL wait, pool waiting).

- **Test taxonomy (AppSignal).** *Load* = how many concurrent users for a period; *stress* = what
  happens at the limit; *performance* = profile one request's time/memory/allocations. **This tool
  is a load + stress tool.** Single-request performance profiling is a different axis, already
  covered in Sabha by `rack-mini-profiler` (dev) and Sentry tracing — we don't rebuild it.

- **AnyCable WS load testing (Evil Martians — the AnyCable authors).** The canonical stack:
  `xk6-cable` for k6, `yabeda-anycable` + `yabeda-prometheus` for RPC metrics, anycable-go's
  Prometheus exporter, Grafana + cAdvisor. We adopt this collection layer wholesale (KD3, KD4).
  Their finding — OSS AnyCable memory-exhausts around ~5k concurrent in their setup — plus Sabha's
  own ~3,400-on-1-vCPU result, make **"where does the wall move per box size?"** a headline
  scenario, not a settled fact. Our differentiator is the **read-out**: one timeline, offered-load
  correlation, and a Rails-vocabulary verdict — not generic Grafana panels.

- **Rails operational habits (RoRvsWild, 2024).** Source of the load-average interpretation rules
  and the capacity/pool-per-thread invariants encoded in the inference engine. Also the environment
  discipline: run the generator from a separate machine near the target, disable sticky sessions,
  whitelist the test IP in any rate limiter, saturate CPU, and sample over several minutes.

- **Legacy `test/performance/` (Rails guides).** The original `ActionDispatch::PerformanceTest` +
  ruby-prof — single-request profiling, removed in Rails 4 (extracted to `rails-perftest`). It's the
  ancestor of the `test/performance/` directory Sabha still uses, but for the profiling job it's
  superseded; not a build input here.

---

## Sabha telemetry inventory (grounded)

**Reuse (already exists):**
- `bin/load-anycable` + `test/performance/chatter.js` — k6 harness, 6 subs/user incl. presence,
  emits connections/sec + messages/sec. Proven in `docs/performance/load-testing.md`.
- `config/environments/performance.rb` — auto-seeds 10k users / 201 rooms / 11k memberships;
  disables WS origin checks. The ready-made load-test target env.
- `script/dev/flood-room`, `script/dev/populate` — hot-room setup + Faker seeding.
- `Room::PresenceSet` → presence HTTP API on :8080 (HMAC-`api-cable` bearer) — a real read of
  who's attached to a stream = real fan-out width.

**Net-new, all cheap:**
- Add Yabeda gems: `yabeda-anycable` (RPC), `yabeda-prometheus` (the `/metrics` endpoint the tool
  scrapes) + plugins for ActiveRecord pool, GVL, and Puma → one scrape covers pool-waiting, GVL
  wait, and thread saturation directly (the signals the results-doc run could only infer).
- Enable anycable-go's Prometheus exporter (one flag) → clients connected, RPC rate/latency,
  broker mem, disconnect rate.

**Confirmed absent today:** `/metrics`, Puma stats socket, Prometheus/OTel/StatsD/Yabeda,
Notifications subscribers. Observability is external/passive (Sentry, Umami, Beszel-on-SaaS) — so
the Yabeda addition is the one real piece of new Sabha code.

---

## First vertical slice

Prove the whole pipeline end-to-end with the fewest new parts, against the `performance` env on a
disposable VPS (the setup `docs/performance/load-testing.md` already validated):

1. Driver wraps `bin/load-anycable` (ramp connections + message rate).
2. Taps: anycable-go metrics (one flag) + presence API. **Yabeda pool/GVL/Puma meters come next.**
3. UI: hardcoded Sabha topology, one live **goodput-vs-offered-load** chart, connections meter.
4. Default scenario: **"one hot room saturates the single writer"** via `flood-room` at rising
   rate.

Then add the Yabeda instrumentation (writer-contention meter + GVL verdict), then the full
topology and remaining meters.

---

## Open questions

- **OQ1. [Resolved] Target environment.** Reuse the proven setup from
  `docs/performance/load-testing.md`: a disposable DO VPS running the image in
  `RAILS_ENV=performance` (auto-seeds 10k users / 201 rooms / 11k memberships), generator on a
  separate machine, never local dev for headline numbers. *Open sub-question:* box size — the
  existing run used 1 vCPU/2 GB and topped out ~3,400 concurrent (AnyCable); the ~10k goal needs
  more cores, and finding *where* the wall moves per box is the tool's job.
- **OQ2. Persist + diff runs in v1?** Save runs and diff two of them after a config change (e.g.
  before/after raising `pool` or `RAILS_MAX_THREADS`) — v1 or later? *Lean: later; single live run
  first.*
- **OQ3. [Decided] Adopt Yabeda in Sabha — implementation deferred.** The Yabeda stack
  (`yabeda-anycable`, `yabeda-prometheus`, + ActiveRecord-pool / GVL / Puma plugins) becomes
  Sabha's real metrics layer, not just a load-test crutch. **Exposure decided: `/metrics` mounts
  in non-prod only** (performance/staging/dev) — zero prod overhead or surface; the load-test
  target runs `RAILS_ENV=performance`, so this fully unblocks the tool. Promote to prod (behind a
  token) later only if the metrics prove useful in production. Phased rollout when built: Phase 1 =
  `yabeda` + `yabeda-prometheus` + `yabeda-anycable` + mount (on a branch cut from `main`, both
  `Gemfile`/`Gemfile.saas` lockfiles synced); Phase 2 = the pool / GVL / Puma / HTTP plugins.

## Out of scope (for now)

- Other apps (Fizzy, Campfire) and any adapter/generalization layer.
- Multi-node / distributed load generation (single-node target is the whole point).
- The teaching/simulator angle (this is measurement, not a model).
- SaaS multi-tenant load profiles (self-hosted single-tenant first).
