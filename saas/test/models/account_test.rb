# frozen_string_literal: true

require_relative "../test_helper"

class SaasAccountTest < ActiveSupport::TestCase
  test "updating account name syncs to workspace record" do
    identity = GlobalIdentity.create!(name: "Sync Test", email_address: "syncname@example.com", verified_at: Time.current)

    with_provisioned_workspace(name: "Original Name", creator: identity) do |workspace|
      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        account = Account.first
        account.update!(name: "Renamed Workspace")
      end

      assert_equal "Renamed Workspace", workspace.reload.name
    end
  ensure
    identity&.destroy
  end

  test "attaching and purging logo syncs has_logo flag on workspace" do
    identity = GlobalIdentity.create!(name: "Logo Sync", email_address: "logosync@example.com", verified_at: Time.current)

    with_provisioned_workspace(name: "Logo Test", creator: identity) do |workspace|
      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        account = Account.first

        account.update!(logo: { io: StringIO.new("fake png"), filename: "logo.png", content_type: "image/png" })
        assert workspace.reload.has_logo?, "expected has_logo to flip true after attach"

        account.purge_logo
        assert_not workspace.reload.has_logo?, "expected has_logo to flip false after purge"
      end
    end
  ensure
    identity&.destroy
  end
end
