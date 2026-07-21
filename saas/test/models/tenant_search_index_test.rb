require_relative "../test_helper"

class TenantSearchIndexTest < ActiveSupport::TestCase
  # Guards the tenant-provisioning hook in Workspace.create_with_database!: the
  # full-text search index lives outside db/schema.rb, so each freshly
  # schema-loaded tenant database must have it provisioned, or the first message
  # indexing callback fails with "no such table: message_search_index".
  test "a provisioned workspace has its full-text search index" do
    with_provisioned_workspace(name: "Search Index", creator: global_identities(:alice)) do |workspace|
      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        assert Message::SearchIndex.exists?
      end
    end
  end

  # Guards the P1 fix: the global db:* provisioning hooks must be gated off in
  # SaaS. Its models are tenanted, so Message.connection during a global task has
  # no tenant — and production has no default tenant to fall back on (unlike
  # dev/test), so an ungated hook would crash boot. prepare_all is stubbed so the
  # test only observes whether our enhancement fires.
  test "db:prepare does not globally provision the search index in SaaS" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("db:prepare")

    ActiveRecord::Tasks::DatabaseTasks.stubs(:prepare_all)
    Message::SearchIndex.expects(:ensure!).never

    Rake::Task["db:prepare"].reenable
    Rake::Task["db:prepare"].execute
  end
end
