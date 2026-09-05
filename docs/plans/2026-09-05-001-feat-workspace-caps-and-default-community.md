---
title: Workspace Caps & Default Community
type: feat
date: 2026-09-05
topic: workspace-caps
status: decision-of-record
supersedes: earlier "single default community" framing (same date)
companion_repo: sabha-desktop
companion_plan: sabha-desktop/docs/plans/2026-09-04-1858-feat-electron-desktop-foundation-plan.md
---

# Workspace Caps & Default Community

## Why this doc exists

The `sabha-desktop` foundation program (multi-server Electron shell) is on an
operator **"Pause for reevaluation" (2026-09-05)** with seven mergeable PRs
stacked: `sabha` #177 (`feat/desktop-protocol-v1`), #178 (`feat/desktop-events`);
`sabha-desktop` #1–#5. That program assumed **sabha.co (SaaS mode) is
many-workspaces-per-user**.

An earlier revision of this doc proposed collapsing sabha.co to a single shared
community with no self-serve creation. **That is superseded.** The decided model
keeps sabha.co multi-workspace but **governs it with caps**: everyone auto-joins
a flagship community, a regular user may create one of their own, superadmins are
uncapped, and anyone may belong to up to twenty. Because multi-workspace stays,
the desktop program's original assumption is **correct again** — so this doc is
now mostly a `sabha`-side governance spec, and the desktop shell needs no
structural change.

## Names (do not conflate)

| Name | What it is |
|---|---|
| **sabha.co** | This repository in **SaaS mode** (`saas/`). Shared communities at path-prefix URLs. |
| **Self-hosted Sabha** | This repository in default single-tenant mode. **One community per instance.** Operators may run **N instances** on their own servers (or anywhere), each a distinct origin. |
| **sabha_cloud** (`cloud.sabha.co`) | A **separate application** (`sabha-co/sabha_cloud`). Control plane that provisions droplets. Not this repo. Not a chat origin. How many droplets it will create is sabha_cloud's concern. |
| **A Cloud-hosted community** | One of those self-hosted instances, deployed by sabha_cloud. From sabha.co and from desktop it is just another origin you add by URL. Same as instance 2…N on the operator's own machines. |

Desktop and the SaaS catalog never special-case sabha_cloud. After a droplet is live, it uses the self-hosted desktop protocol.

## The model (2026-09-05)

sabha.co (SaaS mode) stays multi-workspace, governed by caps:

1. **Flagship default community.** Every GlobalIdentity is **auto-joined** at
   signup to one designated flagship — `1000101` ("Sabha Chat"), the existing
   example community — via `DEFAULT_COMMUNITY_ID`. Nobody sees an empty rail; it
   is the shared home.
2. **Own one.** A regular SaaS user may create **one** workspace of their own
   (`MAX_WORKSPACES` 10 → 1).
3. **Superadmin uncapped.** Superadmins bypass **every** cap — unlimited creation
   and unlimited memberships (to seed the flagship and any curated communities).
4. **Belong to twenty.** Any user may be a member of up to **20 workspaces
   total**, counting the flagship, their own, and invited ones. New cap; none
   exists today.
5. **Multi-workspace UI stays.** The web workspace selector remains; users switch
   among their memberships as before. Path-prefix addressing unchanged
   (`sabha.co/{external_id}`); no subdomain move.
6. **Joining by invite surfaces the workspace in the selector.** Redeeming an
   invite creates a `WorkspaceMembership`, so the joined community appears in the
   selector automatically — on **web** (the existing rail lists
   `workspace_memberships_ordered.user_active`, shown on next load) and on
   **desktop** (the native rail, after the authenticated SaaS catalog refreshes).
   No manual "add" step for sabha.co communities; self-hosted origins still use
   add-by-URL.

Self-hosted single-tenant mode is unaffected — always one community, no caps.

Beyond the one workspace a user may create on sabha.co, "your own community" =
**self-host an instance** (your own box or a sabha_cloud droplet) and add it to
the desktop rail by URL. sabha.co does not count or cap those origins.

## Desktop program: unaffected

The superseded revision would have collapsed the SaaS destination catalog to one
peer and hidden the selector. **Neither applies now.** Multi-workspace stays, so:

- The SaaS destination catalog returns **many workspace peers** sharing one
  sabha.co cookie jar — exactly as the desktop program already built (KTD3/KTD4,
  `sabha` #177). No catalog reconcile.
- The **web workspace selector stays** — no desktop-mode divergence to change.
- Everything else the program built stands unchanged: per-origin partitions
  (KTD3), isolated `WebContentsView` reusing each server's UI (KTD2), self-hosted
  manifest + `sabha://` SSO handoff (KTD4/9), notifications + aggregate badges
  (KTD5), tray/permissions/installers (desktop #1–#5).

One behavior to verify (not a structural change): an **in-session invite join**
must surface the new peer in the native rail via a catalog refresh. The program
already refreshes the authenticated SaaS catalog after sign-in (U3 step 4);
extend that to also refresh on return to the SaaS peer (or after a join) so the
rail updates without a full re-auth — mirroring the web selector, which shows a
newly-joined workspace on the next load.

The only companion-plan cleanup still worth doing is **terminology**: the desktop
plan calls sabha.co SaaS communities "Sabha Cloud workspaces" (R6, R10, KTD3 —
"Cloud workspaces share their origin's authenticated cookie jar"), colliding with
the separate `sabha_cloud` product. Rename those to "sabha.co communities";
`sabha_cloud` droplets are **self-hosted origins**, not SaaS peers.

## Sabha-side changes (this repo)

1. **Auto-join the flagship default at signup.**
   - `DEFAULT_COMMUNITY_ID` env → `1000101`, resolved once at boot (no schema
     change).
   - Auto-join every new GlobalIdentity through the identity-creation path
     (`saas/app/models/global_identity/joinable.rb` `join`), idempotent like the
     existing `find_or_create_by!`.
   - **No backfill.** Forward-only for new signups — existing identities are not
     retro-joined and existing workspaces are not migrated (prod check below).
2. **Cap self-serve creation at 1 (superadmin uncapped).**
   - `MAX_WORKSPACES` 10 → 1 (`saas/app/models/global_identity.rb:14`);
     `workspace_limit_reached?` returns false when the identity is `superadmin`.
   - Keep the `create`/`new` flow and `Workspace.create_with_database!` — only the
     cap changes.
   - Copy: the "maximum of 10 workspaces" message (`Saas::WorkspacesController`)
     becomes "you can create one community — self-host or use Sabha Cloud for
     more."
3. **Cap memberships at 20 (superadmin uncapped).**
   - New `MAX_MEMBERSHIPS = 20`, enforced in `GlobalIdentity#join` / invite
     redemption before `workspace_memberships.find_or_create_by!`. Counts all
     active memberships (flagship + own + invited). Superadmin bypass.
   - Over-cap join is blocked with a clear message. Nobody is near 20 today (36
     workspaces total), so no membership grandfathering.
4. **Keep the web workspace selector.** No change to `show_workspace_selector?`
   (`saas/app/helpers/workspace_selector_helper.rb`) — multi-workspace remains.
5. **Copy / positioning.** Landing FAQ
   (`saas/app/views/saas/landing/show.html.erb`): on sabha.co you get the flagship
   plus one community of your own; run more by self-hosting (your box or Sabha
   Cloud) and adding them in the desktop app. Custom-domain stays a
   self-hosted / Sabha Cloud feature, not a sabha.co one.

## Prod data check (2026-09-05) — no backfill needed

`bin/rails query` (untenanted): **36 workspaces, 29 creators, 4 multi-creators.**
Three are internal — `ashwin@sabha.co` (superadmin, incl. flagship `1000101`),
`ashwinmk2016@gmail.com` (owner's own), `tejas-shetty@outlook.com` (test) — and
only one is a real external duplicate: **Alice** (`selfsoness@gmail.com`), whose
extra (`AirRE`, `1000131`) was a single-member, zero-activity throwaway,
**suspended manually 2026-09-05** (`Workspace#suspend!`, reversible; note the
suspension request-gate is still a no-op TODO in
`admin/workspace_suspensions_controller.rb`). Dropping `MAX_WORKSPACES` to 1 is
creation-time only, so the three internal multi-owners keep what they have. No
one-time backfill job, no data migration.

## Resolved decisions

- **Flagship identity:** `1000101` ("Sabha Chat"), the existing example community;
  `DEFAULT_COMMUNITY_ID` points at it.
- **Caps:** own 1 (superadmin ∞); member of ≤ 20 total incl. flagship + own
  (superadmin ∞).
- **Legacy:** leave as-is; go-forward only; no backfill.
- **Tiers:** flat for now; allowing "own > 1" as a paid lever is a future option,
  not built.

## Restart path

1. Ship the `sabha`-side caps as one PR on `feat/workspace-caps`: auto-join
   flagship, `MAX_WORKSPACES` → 1 + superadmin bypass, `MAX_MEMBERSHIPS` = 20 +
   superadmin bypass, copy updates.
2. Unpause the desktop stacks (`sabha` #177/#178, desktop #1–#5) — no structural
   change; the multi-peer catalog assumption holds.
3. Land the companion-plan terminology fix ("Sabha Cloud workspaces" →
   "sabha.co communities").
