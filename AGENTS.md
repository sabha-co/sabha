# Repository Guidelines

Sabha is a Ruby on Rails chat application using Hotwire/Turbo, AnyCable-Go, Tailwind CSS v4 via `@tailwindcss/cli`, and Importmap. It supports self-hosted single-tenant mode and SaaS multi-tenant mode through `activerecord-tenanted` and the engine in `saas/`; SaaS mode is selected with `SAAS=true` or the `tmp/saas.txt` marker.

## Project Structure & Module Organization
- Rails app code lives in `app/` (models, controllers, views, channels, jobs, mailers).
- Frontend assets: `app/javascript/` (Tailwind CSS source, Stimulus controllers) and `app/assets/`.
- Configuration in `config/`, database migrations in `db/migrate/`.
- Tests: `test/` (self-hosted) and `saas/test/` (SaaS multi-tenant).
- Multi-tenant SaaS engine code lives under `saas/` (models, controllers, initializers, views).
- Docs in `docs/`, including `docs/multi-tenant/` for SaaS architecture.

## Build, Test, and Development Commands
- `bin/setup` — install gems/pnpm, prepare DB, build Tailwind once.
- `bin/dev` — start Rails, the Tailwind watcher, and required `anycable-go` (jobs run in the web process).
- `bin/boot` — start the container app processes (web + Redis + workers); AnyCable-Go runs separately.
- `bin/rails db:migrate` — migrate database.
- `SAAS=true bin/rails db:migrate:primary` — migrate SaaS tenanted and untenanted databases.
- `bin/rails test` — run self-hosted tests.
- `bin/rails test test/models/user_test.rb` — run one self-hosted test file.
- `SAAS=true bin/rails test saas/test/` — run SaaS test suite.
- `pnpm run build:css:watch` — rebuild Tailwind CSS continuously.
- Enable SaaS with `bin/rails saas:enable && bundle install && bin/rails saas:setup`; disable it with `bin/rails saas:disable && bundle install`.
- When changing gems in `Gemfile`, also run `BUNDLE_GEMFILE=Gemfile.saas bundle install` to keep both lockfiles synchronized.

## Coding Style & Naming Conventions
- Follow Rails conventions: 2-space indentation, snake_case for files/methods, CamelCase for classes.
- Keep controllers RESTful and around 5-10 lines per action; create a resource/controller instead of adding custom actions such as `leave`, `activate`, or `process`.
- Keep business logic in models. Methods ending in `!` must raise on failure; return booleans or raise exceptions instead of returning status symbols such as `:success` or `:error`.
- Use named methods for `after_*_commit` callbacks and declare callbacks separately so each retains its own error boundary. Keep delivery behavior in models; controllers only decide when to trigger it.
- When adding associations, update the model's `destroy_all_associated_records`; scoped associations can cause `dependent: :destroy` to miss inactive rows.
- Put genuine shared concerns in `app/models/concerns` or `app/controllers/concerns`, but do not extract small chunks for appearance. Prefer namespace decomposition such as `User::Role` or `Message::Searchable` over service/form/policy layers unless measurable pain justifies them.
- Favor model-based streams (`stream_for`) for ActionCable/Turbo where possible.
- Use `ApplicationRecord` (not `ActiveRecord::Base`) in multi-tenant code paths.

## Key Domain Knowledge
- `Room` uses STI. Current types include `Rooms::Open`, `Rooms::Closed`, `Rooms::Direct`, `Rooms::Thread`, `Rooms::Forum`, and `Rooms::Post`; a `Rooms::Thread` is tied to a parent message.
- Messages, rooms, and memberships are soft-deleted through the `Deactivatable` concern and its `active` flag. Boosts and bookmarks are hard-deleted.
- Mentions are stateless for real-time delivery and persistent through history notifications. They are parsed from Action Text HTML by `Message::Mentionee`; there is no mentions table. `Notification` records power Activity and unread badges, and `@everyone` uses `messages.mentions_everyone`.
- Self-hosted authentication uses `Session` and password/email OTP through `AuthToken`, with request state in `Current.user`, `Current.session`, and `Current.account`. SaaS authentication uses `GlobalIdentity`, `AuthCode`, `GlobalSession`, and `WorkspaceMembership`; the workspace membership determines `Current.user`.

## Real-time & AnyCable Guidelines
- AnyCable-Go is a required runtime dependency, not an optional ActionCable adapter. Development starts it on port 8080 through `bin/dev`; production must run it as a separate sidecar/process routed at `/cable` and calling Rails over HTTP RPC at `/_anycable`. Kamal configures it as an accessory in `config/deploy.yml` and `config/deploy.multitenant.yml`; Docker Compose is also supported. There is no Rails-only WebSocket mode.
- Channel classes still use ordinary ActionCable APIs. Configuration lives in `config/anycable.yml` and `config/cable.yml`; non-test environments use `any_cable`, while tests use the `test` adapter.
- Presence uses `AnyCable::Rails::Channel::Presence`. Do not call `leave_presence` from `on_unsubscribe` or another teardown callback: AnyCable removes presence automatically on unsubscribe/disconnect. Use an explicit leave only for an away state while the subscription remains active.
- Presence and stream history currently use AnyCable's in-memory broker, so deployments run one AnyCable-Go replica. More than one replica requires a shared broker such as Redis or NATS so presence does not fragment.
- `ANYCABLE_PRESENCE_TTL` is set explicitly (45s) in every launch point rather than left at the 15-second default. It is how long push stays suppressed after a socket dies silently, so it must clear the client's worst-case reconnect (~34s) or a network blip pushes someone who never left the room.
- Rails reads the presence set over AnyCable-Go's HTTP API (`Room::PresenceSet`) to decide who gets a push. Two things to know before touching it: the API secret is not `ANYCABLE_SECRET` but `HMAC-SHA256(ANYCABLE_SECRET, "api-cable")`, which AnyCable-Go derives unless `--api_secret` is passed; and AnyCable-Go *disables* the API entirely when it is unprotected, so a missing secret does not expose presence — it silently makes every read fail, which fails push open. Keep a secret set and keep `--api_port`/`--public` unset.
- **AnyCable-Go 1.6.9 is the minimum version.** The HTTP API was added in 1.6.9; 1.6.8 and earlier have no `/api` server, so every presence read 404s and push gating silently falls back to the `connected_at` column. Nothing fails loudly — check for `Handle API requests at … (authorization required)` in the AnyCable-Go startup log, or watch for `[presence] … unavailable: HTTP 404` in the Rails log.
- Sockets use JWT identification so reconnects can skip the Rails connect RPC. Keep JWT and signed-stream secrets aligned between Rails and AnyCable-Go.
- Official documentation: https://docs.anycable.io; LLM-readable text: https://docs.anycable.io/llms-full.txt.

## Testing Guidelines
- Frameworks: Minitest, mocha, webmock; system tests via capybara/cuprite.
- Test files end in `_test.rb`.
- SaaS tests live in `saas/test/` and run only with SaaS mode enabled.
- After changes, run the relevant test suite; for SaaS changes, run both `bin/rails test` and `SAAS=true bin/rails test saas/test/`.
- Prefer tenant-safe fixtures and ensure `Current.reset` is called in test teardowns.
- Test data strategy: real database, fixtures loaded once (`fixtures :all` or explicit fixture lists), and per-test transactional rollback (default Rails `use_transactional_tests`).

## Commit & Pull Request Guidelines
- Commit messages are short, imperative, and capitalized (e.g., “Fix …”, “Add …”, “Refactor …”).
- PRs should describe scope, include relevant test commands run, and link related issues/docs.
- For UI changes, include screenshots or a short GIF.

## Configuration & Environment Tips
- Self-hosted mode uses SQLite in production. SaaS uses PostgreSQL for shared untenanted records (`UntenantedRecord`, migrations in `saas/db/untenanted_migrate/`, schema in `saas/db/untenanted_schema.rb`) and one SQLite database per workspace for application records (`ApplicationRecord`, migrations in `db/migrate/`).
- SaaS mode uses `Gemfile.saas`; tenant databases live under `storage/workspaces/{env}/{tenant}/db/main.sqlite3`.
- Path-based tenant routing uses URLs like `/1000001/rooms/general`.
- Tailwind source is `app/javascript/entrypoints/application.css`; output is `app/assets/builds/tailwind.css`. The project uses the Tailwind CLI through pnpm, with no Vite or JavaScript bundler.

## UI & Styling Guidelines
- Before changing CSS or views, ask for concrete colors, backgrounds, and visual references, then summarize the proposed visual changes before editing.
- Design for community-oriented chat: hobbyist groups, open-source projects, and interest-based collectives should feel that the space is owned and personal rather than corporate.
- Preserve the product's warm, simple, reliable character: content-first layouts, minimal chrome, generous whitespace, and restrained personality rather than generic dashboard styling.
- Express warmth through thoughtful defaults and subtle avatar colors, spacing, and transitions rather than decoration or illustration.
- Use Campfire/HEY as visual references. Avoid Discord-like feature density, generic SaaS dashboards, and dark gamer aesthetics; light mode is the primary experience and typography uses the system font stack with the existing six-level size scale.
- Prefer immediate clarity over clever interactions: no mystery-meat navigation or important features hidden behind gestures.
- Design mobile and desktop states together, using an overlay sidebar on mobile and a docked sidebar on desktop. Maintain WCAG AA contrast, keyboard and screen-reader support, and inputs sized at `max(16px, 1em)`.
- Use the existing light/dark OKLch tokens. Blues are interactive, warm earth tones identify people, grays provide structure, purple provides emphasis, and red is reserved for destructive or negative actions.

## Context & Deeper Documentation
- When handing off or compacting work, preserve modified-file lists, failing test output, and architectural decisions.
- Treat `CLAUDE.md` as the detailed architecture and product-design reference; consult `docs/multi-tenant/` for SaaS workflows.
