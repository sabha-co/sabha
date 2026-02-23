# frozen_string_literal: true

# Automatically migrate SaaS tenant databases after self-hosted migrations.
# When running `bin/rails db:migrate` in self-hosted mode, this detects
# Gemfile.saas.lock (indicating SaaS is set up) and shells out to also
# migrate tenants. Eliminates the manual `SAAS=true bin/rails db:migrate` steps.

Rake::Task["db:migrate"].enhance do
  saas_lockfile = Rails.root.join("Gemfile.saas.lock")
  next if Sabha.saas?
  next unless File.exist?(saas_lockfile)

  env = {
    "SAAS" => "true",
    "BUNDLE_GEMFILE" => Rails.root.join("Gemfile.saas").to_s
  }

  puts "\n--- Migrating SaaS tenant databases..."
  ok = Bundler.with_unbundled_env do
    system(env, "bin/rails", "db:migrate:primary")
  end
  abort "SaaS tenant migration failed" unless ok

  puts "\n--- Migrating SaaS untenanted database..."
  ok = Bundler.with_unbundled_env do
    system(env, "bin/rails", "db:migrate:untenanted")
  end
  abort "SaaS untenanted migration failed" unless ok
end
