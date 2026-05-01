# Migrating a SaaS Workspace to Self-Hosted

A workspace administrator on a Sabha SaaS instance can download their workspace's database and use it directly to spin up a self-hosted Sabha server. The downloaded SQLite file *is* a self-hosted database — same schema, same data, byte-equivalent to a clean snapshot of the live tenant.

## What's included

- Users (with email addresses, names, roles, badges, profiles)
- All rooms (Open, Closed, Direct, Threads) and their memberships
- All messages, including reactions (boosts), bookmarks, and the FTS5 search index
- Webhooks, push subscriptions, bans, blocks, notifications
- The workspace's `Account` settings (custom styles, permissions)

## What's not included

- **File attachments and avatars.** Active Storage blob *records* travel in the SQLite, but the underlying files do not. Avatars and attached images will appear broken on the self-hosted side.
- **SaaS authentication state.** Every user re-authenticates on the self-hosted instance using the email-OTP flow. Old sessions are dead.
- **Cross-workspace identity.** The export clears `users.workspace_membership_id` so there are no dangling references to SaaS-only tables.

## How to download

1. Sign in to your workspace as an administrator.
2. Open the export page at `/{workspace_id}/settings/export`.
3. Click **Email me a download link**. A background job snapshots the workspace, gzips it, uploads it to private storage, and emails a signed download link to your administrator email address.
4. Click the link in the email to download `sabha-workspace-{external_id}-{timestamp}.sqlite3.gz`. The link expires 24 hours after the email is sent.
5. Decompress: `gunzip sabha-workspace-…sqlite3.gz`.

## How to boot a self-hosted Sabha with it

1. Set up a fresh self-hosted Sabha checkout following [the standard setup](../DEPLOYMENT.md).
2. Stop the server if it's running.
3. Replace the database file at `storage/${RAILS_ENV}.sqlite3` (e.g. `storage/production.sqlite3`) with the decompressed `.sqlite3` file.
4. Start the server.

That's it — no migration step is needed. The exported database already has all of Sabha's migrations applied.

## Operator requirements

Exports use the same R2 bucket that workspace backups use (`R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT`, `R2_BUCKET`). When R2 isn't configured, the export page shows a "not configured" alert and the button is a no-op.

## First login

Use **"Sign in with email"** on the login page. Whoever was an administrator in the SaaS workspace remains an administrator on the self-hosted instance.

To bring members along, either invite them (they'll get a fresh email-OTP link) or notify them to sign in with their existing email — the system will recognize them and send a sign-in link.

## Caveats

- Avatars and message attachments will be broken until you either upload new ones or restore the underlying blob files separately. Re-uploading avatars is usually the simplest path.
- This is a snapshot, not a sync. Any messages sent in the SaaS workspace *after* you downloaded will not be in the self-hosted instance.
- The export does not delete the workspace from the SaaS side. If you want to fully migrate, delete the workspace from SaaS after confirming the self-hosted instance is working.
