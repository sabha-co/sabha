# frozen_string_literal: true

require_relative "../test_helper"

class AvatarsNoTenantTest < ActionDispatch::IntegrationTest
  test "avatar request without workspace prefix responds 404 instead of 500" do
    identity = GlobalIdentity.create!(
      name: "Avatar Tester",
      email_address: "avatar@example.com",
      verified_at: Time.current
    )

    with_provisioned_workspace(name: "Avatar WS", creator: identity) do |workspace|
      token = ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        User.first.avatar_token
      end

      get "/users/#{token}/avatar"

      assert_response :not_found
    end
  ensure
    identity&.destroy
  end
end
