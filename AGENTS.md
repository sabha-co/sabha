# Repository Guidelines

## Project Structure & Module Organization
- Rails app code lives in `app/` (models, controllers, views, channels, jobs, mailers).
- Frontend assets: `app/frontend/` (Tailwind CSS source, Stimulus controllers) and `app/assets/`.
- Configuration in `config/`, database migrations in `db/migrate/`.
- Tests: `test/` (self-hosted) and `saas/test/` (SaaS multi-tenant).
- Multi-tenant SaaS engine code lives under `saas/` (models, controllers, initializers, views).
- Docs in `docs/`, including `docs/multi-tenant/` for SaaS architecture.

## Build, Test, and Development Commands
- `bin/setup` — install gems/pnpm, prepare DB, build Tailwind once.
- `bin/dev` — start dev server (jobs in web process).
- `bin/boot` — full stack (web + redis + workers).
- `bin/rails db:migrate` — migrate database.
- `bin/rails test` — run self-hosted tests.
- `SAAS=true bin/rails test saas/test/` — run SaaS test suite.
- SaaS mode toggle: `bin/rails saas:enable` / `bin/rails saas:disable` (run `bundle install` after switching).

## Coding Style & Naming Conventions
- Follow Rails conventions: 2-space indentation, snake_case for files/methods, CamelCase for classes.
- Keep concerns in `app/models/concerns` or `app/controllers/concerns`.
- Favor model-based streams (`stream_for`) for ActionCable/Turbo where possible.
- Use `ApplicationRecord` (not `ActiveRecord::Base`) in multi-tenant code paths.
- Avoid non-RESTful controller actions and keep business logic out of controllers.

## Testing Guidelines
- Frameworks: Minitest, mocha, webmock; system tests via capybara/cuprite.
- Test files end in `_test.rb`.
- SaaS tests live in `saas/test/` and run only with SaaS mode enabled.
- Prefer tenant-safe fixtures and ensure `Current.reset` is called in test teardowns.
- Test data strategy: real database, fixtures loaded once (`fixtures :all` or explicit fixture lists), and per-test transactional rollback (default Rails `use_transactional_tests`).

## Commit & Pull Request Guidelines
- Commit messages are short, imperative, and capitalized (e.g., “Fix …”, “Add …”, “Refactor …”).
- PRs should describe scope, include relevant test commands run, and link related issues/docs.
- For UI changes, include screenshots or a short GIF.

## Configuration & Environment Tips
- SaaS mode uses `Gemfile.saas` and a per-workspace SQLite layout.
- Path-based tenant routing uses URLs like `/1000001/rooms/general`.
- Check `CLAUDE.md` for deeper architecture notes and SaaS workflows.
