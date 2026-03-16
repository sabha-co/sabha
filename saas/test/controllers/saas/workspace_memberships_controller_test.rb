# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class WorkspaceMembershipsControllerTest < ActionDispatch::IntegrationTest
    test "reorder requires authentication" do
      patch "/workspace_memberships/reorder",
            params: { workspace_ids: [ "1000001" ] },
            as: :json

      assert_response :redirect
    end

    test "reorder updates position for workspace memberships" do
      identity = global_identities(:alice)
      sign_in_global_identity(identity)

      # Alice has memberships in fixtures (acme and shared)
      workspace_acme = workspaces(:acme)
      workspace_shared = workspaces(:shared)

      # Reorder - put shared before acme
      patch "/workspace_memberships/reorder",
            params: { workspace_ids: [ workspace_shared.external_id.to_s, workspace_acme.external_id.to_s ] },
            as: :json

      assert_response :ok

      # Verify positions are updated
      membership_acme = identity.workspace_memberships.find_by(tenant: workspace_acme.external_id.to_s)
      membership_shared = identity.workspace_memberships.find_by(tenant: workspace_shared.external_id.to_s)

      assert_equal 1, membership_acme.position
      assert_equal 0, membership_shared.position
    end

    test "reorder returns unprocessable_entity for empty workspace_ids" do
      identity = global_identities(:alice)
      sign_in_global_identity(identity)

      patch "/workspace_memberships/reorder",
            params: { workspace_ids: [] },
            as: :json

      assert_response :unprocessable_entity
    end

    test "reorder ignores workspaces user is not a member of" do
      identity = global_identities(:charlie)
      sign_in_global_identity(identity)

      # Try to reorder a workspace Charlie isn't a member of (acme belongs to alice)
      workspace = workspaces(:acme)

      patch "/workspace_memberships/reorder",
            params: { workspace_ids: [ workspace.external_id.to_s ] },
            as: :json

      assert_response :ok

      # Charlie should NOT gain a membership to acme
      assert_not identity.workspace_memberships.exists?(tenant: workspace.external_id.to_s)
    end
  end
end
