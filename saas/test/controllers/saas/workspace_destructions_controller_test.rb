# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class WorkspaceDestructionsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @workspace = Workspace.create_with_database!(
        name: "Test Workspace",
        creator: global_identities(:alice)
      )
      @session = sign_in_global_identity(global_identities(:alice))
    end

    teardown do
      @workspace&.destroy_with_database! if Workspace.exists?(id: @workspace&.id)
    end

    test "requires administrator role" do
      # Sign in as a non-admin member
      charlie_membership = WorkspaceMembership.create!(
        global_identity: global_identities(:charlie),
        tenant: @workspace.external_id.to_s
      )
      charlie_membership.create_user!(role: :member)

      sign_in_global_identity(global_identities(:charlie))

      workspace_post "/destruction", workspace: @workspace, params: { confirmation: @workspace.name }

      assert_response :forbidden
    end

    test "requires matching confirmation" do
      workspace_post "/destruction", workspace: @workspace, params: { confirmation: "wrong name" }

      assert_redirected_to "/#{@workspace.external_id}/settings"
      assert_equal "Workspace name did not match.", flash[:alert]
      assert Workspace.exists?(id: @workspace.id)
    end

    test "with correct confirmation deletes workspace" do
      external_id = @workspace.external_id

      workspace_post "/destruction", workspace: @workspace, params: { confirmation: @workspace.name }

      assert_redirected_to workspaces_url(script_name: "")
      assert_match /deleted/, flash[:notice]
      assert_not Workspace.exists?(external_id: external_id)

      @workspace = nil  # Prevent teardown from trying to destroy
    end

    test "emails all admins" do
      # Add a second admin
      bob_membership = WorkspaceMembership.create!(
        global_identity: global_identities(:bob),
        tenant: @workspace.external_id.to_s
      )
      bob_membership.create_user!(role: :administrator)

      perform_enqueued_jobs do
        workspace_post "/destruction", workspace: @workspace, params: { confirmation: @workspace.name }
      end

      alice_email = global_identities(:alice).email_address
      bob_email = global_identities(:bob).email_address
      deletion_emails = ActionMailer::Base.deliveries.select { |m| m.subject.include?("deleted") }

      assert_equal 2, deletion_emails.size
      assert_equal [ alice_email ], deletion_emails.find { |m| m.to.include?(alice_email) }.to
      assert_equal [ bob_email ], deletion_emails.find { |m| m.to.include?(bob_email) }.to

      @workspace = nil
    end
  end
end
