---
title: Workspace Caps & Default Workspace
type: feat
date: 2026-09-05
topic: workspace-caps
status: decision-of-record
---

# Workspace Caps & Default Workspace

## Why

Unlimited self-serve creation on sabha.co was producing throwaway workspaces, and
new sign-ups landed on an empty selector. sabha.co stays multi-workspace, but
governed: everyone lands in one shared workspace, a regular user creates one of
their own, and anything beyond that is a self-hosted workspace.

## Names

| Name | What it is |
|---|---|
| **sabha.co** | This repository in SaaS mode (`saas/`). Many workspaces at path-prefix URLs. |
| **Self-hosted Sabha** | This repository in default single-tenant mode. One workspace per install; operators may run as many installs as they like, each its own origin. |
| **Sabha Cloud** (`cloud.sabha.co`) | A separate application (`sabha-co/sabha_cloud`) that provisions self-hosted installs. Not a chat origin. |

A Sabha Cloud droplet is a self-hosted workspace like any other. It can pair
with sabha.co and appear in its owner's list (see
`docs/plans/2026-09-23-001-feat-connected-instances-plan.md`).

## The model

1. **Default workspace.** Every new `GlobalIdentity` joins `1000101` ("Sabha
   Chat", `GlobalIdentity::DEFAULT_WORKSPACE_ID`) once its sign-up code is
   verified, so its user there starts verified too. Skipped if
   that workspace doesn't exist. Forward-only: existing identities aren't
   backfilled.
2. **Create one.** A regular user may create one workspace (`MAX_WORKSPACES`
   10 → 1). Creation-time only, so existing owners keep what they have.
3. **Belong to twenty.** A user may be in at most 20 sabha.co workspaces
   (`MAX_MEMBERSHIPS`), counting the default one, their own and invited ones.
   Enforced in `GlobalIdentity#join` under the identity row lock, so invites and
   creation both respect it. Coming back to a workspace you left counts as a
   join. Self-hosted entries in a person's list don't count.
4. **Superadmins** bypass both caps, to seed the default workspace and any
   curated ones.
5. **Beyond the cap**, the answer is a self-hosted workspace: run Sabha yourself
   or on Sabha Cloud, and add it from the selector's **+**. The create form's
   limit message says so.

Self-hosted single-tenant mode is unaffected: one workspace, no caps.

## Desktop

The desktop app draws its own workspace rail, so the web selector stays hidden
there (`show_workspace_selector?`, unchanged). What changes is that the app
never lands on marketing pages: the landing page, about, changelog and openclaw
send it to sign-in, or to the member's most recent workspace, and the auth pages
drop their "Back" and logo links to the landing page.

## Prod data check (2026-09-05)

36 workspaces, 29 creators, 4 with more than one. Three of those are internal.
The one external duplicate was a single-member, inactive throwaway and was
suspended by hand. Nobody is near 20 memberships. No backfill or data migration.

## Decisions

- **Default workspace:** `1000101`, a constant rather than a setting; the
  marketing pages already link to it.
- **Caps:** create 1, belong to 20, superadmins uncapped.
- **Tiers:** flat for now. "Create more than one" as a paid option is a future
  lever, not built.
