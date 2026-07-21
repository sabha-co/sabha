namespace :db do
  desc "Provision the full-text search index for the current adapter (idempotent)"
  task ensure_search_index: :environment do
    Message::SearchIndex.ensure!
  end
end

# The search index lives outside db/schema.rb (see Message::SearchIndex), so no
# schema-load path creates it. Provision it after every self-hosted database
# setup entry point — db:prepare (boot, CI, bin/setup) and the schema-load/reset
# commands a developer might run directly (db:schema:load, db:setup, db:reset).
# Message::SearchIndex.ensure! is idempotent, so the overlapping hooks (e.g.
# db:reset → db:setup → db:schema:load) are no-ops after the first.
#
# SaaS is excluded: its application models are tenanted, so there is no Message
# connection during a global db:* task — production has no default tenant (unlike
# dev/test, see saas/config/initializers/tenanting/default_tenant.rb), so calling
# Message.connection here would raise and abort boot. The untenanted database has
# no messages; SaaS provisions each tenant's index in Workspace.create_with_database!.
unless Sabha.saas?
  %w[ db:prepare db:schema:load db:setup db:reset ].each do |name|
    Rake::Task[name].enhance { Message::SearchIndex.ensure! } if Rake::Task.task_defined?(name)
  end
end
