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
end
