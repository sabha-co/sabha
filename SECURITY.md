# Security Policy

## Reporting a vulnerability

Please report security vulnerabilities **privately** — do not open a public issue, pull request, or discussion.

Email **ashwin[at]sabha.co** with:

- A description of the vulnerability and its impact
- Steps to reproduce (proof-of-concept if you have one)
- Any relevant logs, versions, or configuration

You can expect an acknowledgement within a few days. If you haven't heard back,
please follow up — it likely means the first email didn't reach us. We're happy to
credit you once the issue is resolved (let us know if you'd prefer to stay anonymous).

Please give us a reasonable window to ship a fix before any public disclosure.

## What to expect

Once we receive your report, we'll:

1. Confirm the issue and determine which versions are affected.
2. Audit the codebase for similar or related problems.
3. Prepare a fix and ship it.
4. Keep you updated as we work through it.

## Supported versions

Sabha ships from `main`. Security fixes land there; please run the latest version
before reporting.

## Trust model

Sabha runs in two deployment modes, and what counts as "trusted" differs between
them. Please keep the distinction in mind when deciding whether something is a
vulnerability.

**Self-hosted (single-tenant, the default).** The administrator *is* the server
operator — they already have shell, network, and database access to the machine
Sabha runs on. A capability that requires the administrator role therefore grants
nothing they do not already have, and is not a vulnerability. We do want reports
of anything a **non-administrator member** can reach that they should not, and of
any credential or network path held by the Sabha process but not by the operator's
own shell.

**SaaS (the hosted service at sabha.co, multi-tenant).** Here the trust boundary
is different: a **workspace administrator is not the server operator**. They have
no shell, host, or database access, and no access to other workspaces. So, in this
mode:

- **Tenant isolation is a security boundary.** Each workspace lives in its own
  database (`activerecord-tenanted`). Any path by which one workspace can read or
  write another workspace's data — or reach the shared untenanted database, the
  host, or the internal network — is a vulnerability. Please report it.
- A workspace administrator reaching internal-network or host resources, or any
  credential held by the Sabha process, is likewise a vulnerability, even though
  the same action by a self-hosted operator would not be.

## Intentional behavior

**Outbound HTTP from the server is restricted, for admins too.** Every
server-initiated request to a user-supplied address — link/URL unfurling
(member-triggered), bot **webhook** delivery, and Web Push endpoints — is
validated through `RestrictedHTTP::PrivateNetworkGuard` (backed by the `surfguard`
gem): the destination is resolved and rejected if it points at a private,
loopback, link-local, or otherwise internal address, and the address is
re-resolved at delivery time to defeat DNS rebinding. Unlike some upstream chat
apps, Sabha does **not** exempt admin-configured webhook URLs from this check —
because in SaaS the person wiring up a bot is a workspace admin, not the server
operator, so an internal-address webhook would be a server-side request forgery
from the host's own network. A self-hosted operator who genuinely needs a bot to
reach an internal service should run that integration outside Sabha rather than
disabling the guard.