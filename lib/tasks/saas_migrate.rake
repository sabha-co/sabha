# frozen_string_literal: true

# In SaaS mode, chain untenanted tasks after primary tasks so you only
# need to run one command:
#   SAAS=true bin/rails db:migrate:primary   # also migrates untenanted
#   SAAS=true bin/rails db:reset:primary     # also resets untenanted

return unless Sabha.saas?

env = {
  "SAAS" => "true",
  "BUNDLE_GEMFILE" => Rails.root.join("Gemfile.saas").to_s
}

Rake::Task["db:migrate:primary"].enhance do
  puts "\n--- Migrating SaaS untenanted database..."
  ok = Bundler.with_original_env do
    system(env, "bin/rails", "db:migrate:untenanted")
  end
  abort "SaaS untenanted migration failed" unless ok
end

Rake::Task["db:reset:primary"].enhance do
  puts "\n--- Resetting SaaS untenanted database..."
  ok = Bundler.with_original_env do
    system(env, "bin/rails", "db:reset:untenanted")
  end
  abort "SaaS untenanted reset failed" unless ok
end
