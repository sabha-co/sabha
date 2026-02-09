# Rebrand Campfire-CE to Sabha

## Context

Campfire-CE is being rebranded to **Sabha**. The multitenant SaaS deployment is already live at **sabha.co**. A future single-tenant managed hosting service will live at **cloud.sabha.co** (currently campfire_cloud — separate task). This plan covers renaming the campfire-ce codebase itself.

## Decisions

- **Full module rename**: `Campfire` → `Sabha` across all Ruby code
- **GlobalID & content-type preserved**: `gid://campfire-ce/...` and `application/vnd.campfire.mention` stay as-is (serialized in existing databases)
- **Docker image**: `ghcr.io/sabha-co/sabha` → `ghcr.io/sabha-co/sabha`
- **campfire_cloud rename**: Separate future task

## Phases

### Phase 1+2: Core Module & SaaS Engine Rename (single atomic commit)

These must ship together — the app won't boot with a half-renamed module.

**Core module:**
- Rename `lib/campfire.rb` → `lib/sabha.rb`, module `Campfire` → `Sabha`
- `config/application.rb` — update require + `module Campfire` → `module Sabha`
- `bin/rails`, `bin/rake` — update require + `Campfire.configure_bundle` → `Sabha.configure_bundle`
- All `Campfire.saas?` → `Sabha.saas?` across ~30 files:
  - `config/routes.rb`, `config/database.yml`, `config/initializers/00_boot_mode.rb`, `config/initializers/branding.rb`, `config/initializers/mailkick.rb`
  - `app/models/` — `application_record.rb`, `current.rb`, `user.rb`, `account.rb`, `room.rb`
  - `app/controllers/concerns/authentication.rb`, `authentication/session_lookup.rb`, `sessions_controller.rb`, `auth_tokens_controller.rb`, `auth_tokens/validations_controller.rb`, `users_controller.rb`, `users/profiles_controller.rb`
  - `app/channels/application_cable/connection.rb`
  - `app/jobs/unread_mentions_notifier_job.rb`
  - `app/views/layouts/application.html.erb`, `accounts/_invite.html.erb`, `users/profiles/_invite_link.html.erb`
  - `db/seeds.rb`
  - `lib/tasks/saas.rake`, `lib/tasks/workspace.rake`, `lib/tasks/generate.rake`

**SaaS engine:**
- Rename directory `saas/lib/campfire/` → `saas/lib/sabha/` (saas.rb, engine.rb, path_rewriter.rb)
- Module `Campfire::Saas` → `Sabha::Saas`, engine_name `campfire_saas` → `sabha_saas`
- Rename gemspec `saas/campfire-saas.gemspec` → `saas/sabha-saas.gemspec`
- `Gemfile.saas` — `gem "campfire-saas"` → `gem "sabha-saas"`
- `saas/Dockerfile` — update COPY path for gemspec
- All `saas/config/initializers/tenanting/` files — update require paths, module refs, `Sabha.saas?`
- Rename Rack env key `env["campfire.workspace_id"]` → `env["sabha.workspace_id"]` (in path_rewriter.rb, tenant_resolver.rb, and connection tests)
- `saas/app/helpers/workspace_selector_helper.rb`, `saas/app/channels/concerns/tenant_context.rb`
- Run `bundle install` to regenerate `Gemfile.saas.lock`

**DO NOT change:**
- `gid://campfire-ce/Everyone/everyone` in `app/models/everyone.rb`
- `gid://campfire/` regex in `lib/rails_ext/action_text_attachables.rb`
- `application/vnd.campfire.mention` anywhere

---

### Phase 3: Configuration

- `config/initializers/session_store.rb` — `_campfire_session` → `_sabha_session` (logs out all users — expected for rebrand)
- `config/cable.yml` — `campfire_*` → `sabha_*` channel prefixes (reconnects naturally on deploy)
- `config/anycable.yml` — `campfire-anycable` → `sabha-anycable` network alias
- `config/initializers/allowed_hosts.rb` — `once.campfire.test` → `once.sabha.test`
- `config/initializers/branding.rb` — default strings: "Campfire Community Edition" → "Sabha", "Campfire" → "Sabha"
- `config/initializers/demo.rb` — `admin@campfirecloud.com` → `admin@sabha.co`
- `config/environments/performance.rb` — seed account name
- `config/environments/production.rb` — update comments
- `.env.sample` — all default APP_NAME, APP_SHORT_NAME, APP_DESCRIPTION, MAILER_FROM_NAME values

---

### Phase 4: Docker & Deployment

- `Dockerfile` + `saas/Dockerfile` — OS user `campfire` → `sabha` (use explicit UID/GID matching existing containers to avoid permission issues)
- `config/deploy.yml` — service: `sabha`, image: `sabha-co/sabha`, network-alias: `sabha-web`, volume: `/disk/sabha/`
- `config/deploy.multitenant.yml` — image: `sabha-co/sabha`
- `bin/setup` — `app_name=sabha`
- `bin/configure` — update comment
- `script/release` — update image refs and GitHub URLs

**Deployment risk:** Volume path change `/disk/campfire/` → `/disk/sabha/` requires symlinking on existing servers before deploy: `ln -s /disk/campfire /disk/sabha`

---

### Phase 5: User-Facing Text & Views

All hardcoded "Campfire" strings in views:
- `app/views/sessions/incompatible_browser.html.erb`
- `app/views/pwa/_install_instructions.html.erb` (4 occurrences)
- `app/views/pwa/_system_settings.html.erb` (9 occurrences)
- `app/views/accounts/edit.html.erb` — version badge
- `app/views/accounts/_invite.html.erb` — invite text
- `app/views/accounts/bots/index.html.erb`
- `app/views/layouts/application.html.erb` — logo alt text, image reference
- `app/controllers/users/push_subscriptions/test_notifications_controller.rb` — "Campfire Test" → "Sabha Test"
- `app/helpers/translations_helper.rb` — 6-language translations
- `app/frontend/controllers/web_share_controller.js` — shared file prefix
- `app/models/first_run.rb` — comments and log messages
- `public/502.html` — loading page title
- `app/assets/images/campfire-icon.png` — rename or replace with Sabha logo

---

### Phase 6: Package & Demo Data

- `package.json` — `"campfire-ce"` → `"sabha"`
- `lib/tasks/generate.rake` — demo account name + all `@campfirecloud.com` email addresses → `@sabha.co`

---

### Phase 7: Tests

- `test/controllers/messages_controller_test.rb` — `once.campfire.test` → `once.sabha.test`
- `saas/test/channels/application_cable/connection_test.rb` — `campfire.workspace_id` → `sabha.workspace_id` (6 occurrences)
- Content-type test references (`application/vnd.campfire.mention`) — **leave as-is**

---

### Phase 8: Documentation

Find-replace "Campfire"/"campfire-ce" → "Sabha"/"sabha" across:
- `README.md`, `CLAUDE.md`, `saas/README.md`
- `campfire-ce-changelog.md` (rename to `CHANGELOG.md`)
- `smallbets-mods.md`
- `docs/BRANDING.md`, `docs/DEPLOYMENT.md`, `docs/DEVELOPMENT.md`
- All other `docs/*.md` and `docs/multi-tenant/*.md` files

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Session cookie rename logs out all users | Expected for rebrand. One-time cost. |
| ActionCable prefix change disconnects WebSockets | Self-healing on reconnect after deploy restart. |
| Docker volume path `/disk/campfire/` → `/disk/sabha/` | Create symlink on server before deploy: `ln -s /disk/campfire /disk/sabha` |
| Docker user UID mismatch on existing volumes | Use explicit `--uid`/`--gid` in Dockerfile matching existing user |
| Bootsnap cache stale after rename | Delete `tmp/cache/bootsnap` on first run |
| `Gemfile.saas.lock` stale after gemspec rename | Run `bundle install` in Phase 1+2 |

## Verification

```bash
# After Phase 1+2: app should boot
bin/dev
SAAS=true bin/dev

# After Phase 7: tests should pass
bin/rails test
SAAS=true bin/rails test saas/test/

# After Phase 4: Docker build should work
docker build -t sabha-co/sabha .
docker build -f saas/Dockerfile -t sabha-co/sabha:latest-multitenant .
```

## Status

All 8 phases completed. Content-type renamed to `application/vnd.sabha.mention` and GlobalIDs to `gid://sabha/`. Remaining "campfire" references are:
- `campfire_cloud` — separate project, renamed separately
- `campfire-icon.png` — image asset filename
- `Once Campfire` / `basecamp/once-campfire` — upstream 37signals product references in docs
