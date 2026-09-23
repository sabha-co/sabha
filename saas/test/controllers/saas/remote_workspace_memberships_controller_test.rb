# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class RemoteWorkspaceMembershipsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @alice = global_identities(:alice)
      sign_in_global_identity(@alice)
      @acme = remote_workspaces(:acme)
      @membership = remote_workspace_memberships(:alice_acme)
    end

    test "hides and shows an entry" do
      patch "/remote_workspace_memberships/#{@membership.id}", params: { remote_workspace_membership: { hidden: "1" } }
      assert @membership.reload.hidden

      patch "/remote_workspace_memberships/#{@membership.id}", params: { remote_workspace_membership: { hidden: "0" } }
      assert_not @membership.reload.hidden
    end

    test "removes an entry" do
      delete "/remote_workspace_memberships/#{@membership.id}"

      assert_redirected_to settings_path
      assert_not RemoteWorkspaceMembership.exists?(@membership.id)
    end

    test "can't touch someone else's entry" do
      bobs = remote_workspace_memberships(:bob_acme)

      assert_raises(ActiveRecord::RecordNotFound) { delete "/remote_workspace_memberships/#{bobs.id}" }
      assert RemoteWorkspaceMembership.exists?(bobs.id)
    end

    test "serves the stored logo to people who list the community" do
      get "/remote_workspaces/#{@acme.id}/logo"

      assert_response :success
      assert_equal "image/png", response.media_type
      assert_equal "png", response.body
      assert_includes response.headers["Cache-Control"], "private"
    end

    test "serves no logo to people who don't list the community" do
      assert_raises(ActiveRecord::RecordNotFound) { get "/remote_workspaces/#{remote_workspaces(:club).id}/logo" }
    end

    test "reorders workspaces and communities together" do
      patch "/workspace_membership_order", params: { workspace_ids: [ "remote:#{@membership.id}", "1000003", "1000001" ] }, as: :json

      assert_response :ok
      assert_equal 0, @membership.reload.position
      assert_equal 1, workspace_memberships(:alice_shared).position
    end
  end
end
