# frozen_string_literal: true

require_relative "../../../test_helper"

module Saas
  module WorkspaceSettings
    class ExportsControllerTest < ActionDispatch::IntegrationTest
      setup do
        # with_provisioned_workspace teardown calls Workspace::Backup.create_from_database!
        # via destroy_with_database! when R2 is configured. Stub it to a no-op so these
        # tests don't reach S3 during teardown.
        Workspace::Backup.stubs(:create_from_database!)
      end

      test "administrator sees the export page" do
        identity = global_identities(:alice)

        with_provisioned_workspace(name: "Export Show Test", creator: identity) do |workspace|
          sign_in_global_identity(identity)

          workspace_get "/settings/export", workspace: workspace

          assert_response :success
          assert_select "button", text: "Email me a download link"
          assert_select "p", text: /#{Regexp.escape(identity.email_address)}/
        end
      end

      test "administrator triggers an async export and gets a flash with their email" do
        identity = global_identities(:alice)
        Workspace::R2.stubs(:configured?).returns(true)

        with_provisioned_workspace(name: "Async Export Test", creator: identity) do |workspace|
          sign_in_global_identity(identity)

          assert_enqueued_with(job: Workspace::ExportJob) do
            workspace_post "/settings/export", workspace: workspace
          end

          assert_redirected_to "/#{workspace.external_id}/settings/export"
          follow_redirect!
          assert_match identity.email_address, flash[:notice].to_s
        end
      end

      test "second create within the cooldown window does not enqueue another job" do
        identity = global_identities(:alice)
        Workspace::R2.stubs(:configured?).returns(true)

        with_provisioned_workspace(name: "Rate Limit Test", creator: identity) do |workspace|
          sign_in_global_identity(identity)

          assert_enqueued_with(job: Workspace::ExportJob) do
            workspace_post "/settings/export", workspace: workspace
          end

          assert_no_enqueued_jobs only: Workspace::ExportJob do
            workspace_post "/settings/export", workspace: workspace
          end

          assert_redirected_to "/#{workspace.external_id}/settings/export"
          follow_redirect!
          assert_match(/already sent/i, flash[:notice].to_s)
        end
      end

      test "show page hides the button after a request and explains the cooldown" do
        identity = global_identities(:alice)
        Workspace::R2.stubs(:configured?).returns(true)

        with_provisioned_workspace(name: "Cooldown View Test", creator: identity) do |workspace|
          sign_in_global_identity(identity)

          workspace_post "/settings/export", workspace: workspace
          workspace_get "/settings/export", workspace: workspace

          assert_response :success
          assert_select "button", text: "Email me a download link", count: 0
          assert_select "p", text: /already sent an export.*to your email/
        end
      end

      test "create refuses with an alert when R2 is not configured" do
        identity = global_identities(:alice)
        Workspace::R2.stubs(:configured?).returns(false)

        with_provisioned_workspace(name: "Unconfigured Test", creator: identity) do |workspace|
          sign_in_global_identity(identity)

          assert_no_enqueued_jobs only: Workspace::ExportJob do
            workspace_post "/settings/export", workspace: workspace
          end

          assert_redirected_to "/#{workspace.external_id}/settings/export"
          follow_redirect!
          assert_match(/aren't configured/, flash[:alert].to_s)
        end
      end

      test "non-administrator member is forbidden on show and create" do
        creator = global_identities(:alice)
        member = global_identities(:bob)

        with_provisioned_workspace(name: "Non-admin Test", creator: creator) do |workspace|
          tenant = workspace.external_id.to_s

          membership = member.workspace_memberships.create!(tenant: tenant)
          ApplicationRecord.with_tenant(tenant) do
            member_user = User.unscoped.find_or_initialize_by(email_address: member.email_address)
            member_user.assign_attributes(
              name: member.name || "Bob",
              workspace_membership_id: membership.id,
              role: :member,
              verified_at: Time.current
            )
            member_user.reactivate if member_user.persisted? && member_user.respond_to?(:deactivated?) && member_user.deactivated?
            member_user.save!
            membership.cache_user_id!(member_user.id)
          end

          sign_in_global_identity(member)

          workspace_get "/settings/export", workspace: workspace
          assert_response :forbidden

          workspace_post "/settings/export", workspace: workspace
          assert_response :forbidden
        end
      end

      test "unauthenticated request is rejected" do
        with_provisioned_workspace(name: "Unauth Test", creator: global_identities(:alice)) do |workspace|
          workspace_post "/settings/export", workspace: workspace
          assert_not_equal 200, response.status
        end
      end
    end
  end
end
