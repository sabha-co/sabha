# frozen_string_literal: true

require_relative "../test_helper"

# Tests for the workspace-scoped join flow in SaaS mode
#
# This tests the UsersController when accessed via workspace-scoped URLs
# (e.g., /1000001/join/ABC123) after the global join route validates and redirects.
#
# Run with: SAAS=true bin/rails test saas/test/controllers/users_controller_join_test.rb

class SaasUsersControllerJoinTest < ActionDispatch::IntegrationTest
  include TurnstileTestHelper

  setup do
    @workspace = workspaces(:acme)
    @alice = global_identities(:alice)
    @bob = global_identities(:bob)

    # Set up tenant database with Account and JoinCode
    setup_workspace_with_join_code(@workspace)
  end

  # ============================================================================
  # GET /workspace_id/join/:join_code (signed out)
  # ============================================================================

  test "join page when signed out shows sign-in options" do
    workspace_get "/join/#{@join_code.code}", workspace: @workspace

    assert_response :success
    # Links should be untenanted (no workspace prefix)
    assert_select "a[href^='/session/new']", text: /Sign in to join/
    assert_select "a[href^='/registration/new']", text: /Create one/
  end

  test "join page when signed out includes return_to parameter in links" do
    workspace_get "/join/#{@join_code.code}", workspace: @workspace

    assert_response :success
    # Check that the sign-in link includes return_to
    assert_select "a[href*='return_to']", minimum: 1
  end

  # ============================================================================
  # GET /workspace_id/join/:join_code (signed in, not a member)
  # ============================================================================

  test "join page when signed in but not a member shows one-click join" do
    # Bob is not a member of acme workspace
    sign_in_global_identity(@bob)

    workspace_get "/join/#{@join_code.code}", workspace: @workspace

    assert_response :success
    assert_select "button", text: /Join/
    assert_select "p", text: /Joining as.*bob@example.com/
    # No name field - one-click join
    assert_select "input[name='user[name]']", count: 0
    assert_select "input[name='user[email_address]']", count: 0
    assert_select "input[name='user[password]']", count: 0
  end

  # ============================================================================
  # GET /workspace_id/join/:join_code (signed in, already a member)
  # ============================================================================

  test "join page when already a member redirects to root" do
    # Alice is already a member of acme workspace
    sign_in_global_identity(@alice)

    # Need to set up user in tenant DB for alice's membership
    setup_user_for_membership(workspace_memberships(:alice_acme))

    workspace_get "/join/#{@join_code.code}", workspace: @workspace

    # Should redirect to root (redirect_signed_in_user_to_root)
    assert_response :redirect
  end

  test "join page redirects banned member away from the guest join flow" do
    sign_in_global_identity(@alice)
    membership = workspace_memberships(:alice_acme)
    setup_user_for_membership(membership)

    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      User.find(membership.user_id).ban
    end

    workspace_get "/join/#{@join_code.code}", workspace: @workspace

    assert_redirected_to "/settings?denied=workspace"
  end

  # ============================================================================
  # POST /workspace_id/join/:join_code (signed out)
  # ============================================================================

  test "submit join form when signed out redirects to sign-in" do
    workspace_post "/join/#{@join_code.code}", workspace: @workspace, params: with_turnstile_response(
      user: { name: "New User" }
    )

    assert_redirected_to "/session/new"
    assert_match /sign in to join/i, flash[:alert]
  end

  # ============================================================================
  # POST /workspace_id/join/:join_code (signed in, not a member) - Success
  # ============================================================================

  test "submit join form creates workspace membership" do
    sign_in_global_identity(@bob)

    assert_difference -> { WorkspaceMembership.count }, 1 do
      workspace_post "/join/#{@join_code.code}", workspace: @workspace, params: with_turnstile_response({})
    end

    membership = WorkspaceMembership.find_by(
      global_identity: @bob,
      tenant: @workspace.external_id.to_s
    )
    assert membership.present?
  end

  test "submit join form creates user with email prefix as name" do
    sign_in_global_identity(@bob)

    workspace_post "/join/#{@join_code.code}", workspace: @workspace, params: with_turnstile_response({})

    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      user = User.find_by(email_address: "bob@example.com")
      assert user.present?
      assert_equal "Bob", user.name
    end
  end

  test "submit join form redeems join code" do
    sign_in_global_identity(@bob)

    initial_count = @join_code.reload.usage_count

    workspace_post "/join/#{@join_code.code}", workspace: @workspace, params: with_turnstile_response({})

    assert_equal initial_count + 1, @join_code.reload.usage_count
  end

  test "submit join form redirects to workspace root with welcome message" do
    sign_in_global_identity(@bob)

    workspace_post "/join/#{@join_code.code}", workspace: @workspace, params: with_turnstile_response({})

    # Allow trailing slash variation in redirect
    assert_response :redirect
    assert_match %r{/#{@workspace.external_id}/?$}, response.location
    assert_match /Welcome to/, flash[:notice]
  end

  test "submit join form caches user_id in workspace membership" do
    sign_in_global_identity(@bob)

    workspace_post "/join/#{@join_code.code}", workspace: @workspace, params: with_turnstile_response({})

    membership = WorkspaceMembership.find_by(
      global_identity: @bob,
      tenant: @workspace.external_id.to_s
    )

    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      user = User.find_by(email_address: "bob@example.com")
      assert_equal user.id, membership.user_id
    end
  end

  # ============================================================================
  # POST /workspace_id/join/:join_code (already a member - race condition)
  # ============================================================================

  test "submit join form when already a member redirects to root" do
    sign_in_global_identity(@alice)

    # Alice is already a member via fixtures
    # The before_action chain (restore_authentication → ensure_workspace_user_exists →
    # redirect_signed_in_user_to_root) will redirect before the create action runs

    workspace_post "/join/#{@join_code.code}", workspace: @workspace, params: with_turnstile_response({})

    # Should be redirected by redirect_signed_in_user_to_root before create action
    assert_response :redirect
    assert_match %r{/#{@workspace.external_id}/?$}, response.location
  end

  test "signed in user with existing membership redirects to root on GET" do
    sign_in_global_identity(@alice)

    # Alice is already a member - the before_action chain handles this
    workspace_get "/join/#{@join_code.code}", workspace: @workspace

    # Should be redirected by redirect_signed_in_user_to_root
    assert_response :redirect
    assert_match %r{/#{@workspace.external_id}/?$}, response.location
  end

  # Note: The "already a member" validation error (ActiveRecord::RecordInvalid)
  # is a race condition edge case that can't be triggered through normal integration
  # tests because ensure_workspace_user_exists and redirect_signed_in_user_to_root
  # handle existing members before the create action runs. The error handling code
  # exists as a safety net for concurrent requests.

  # ============================================================================
  # POST /workspace_id/join/:join_code (code goes inactive between before_action
  # and the redemption lock — the lost-race window inside create_for_saas_user)
  # ============================================================================

  test "submit join form when code goes inactive between gating and lock redirects with alert" do
    sign_in_global_identity(@bob)

    # active? is true at before_action gating, false once redeem_if acquires the lock.
    # Achieved by stubbing only inside the controller action via the lock callback.
    Account::JoinCode.any_instance.expects(:active?).at_least_once.returns(true).then.returns(false)

    initial_membership_count = WorkspaceMembership.count
    initial_usage = @join_code.usage_count

    workspace_post "/join/#{@join_code.code}", workspace: @workspace, params: with_turnstile_response({})

    assert_response :redirect
    assert_match /no longer valid/, flash[:alert]
    assert_equal initial_membership_count, WorkspaceMembership.count, "no membership should be created"
    assert_equal initial_usage, @join_code.reload.usage_count, "code must not be burned"
  end

  # ============================================================================
  # POST /workspace_id/join/:join_code (invalid join code)
  # ============================================================================

  test "submit join form with invalid code redirects with alert" do
    sign_in_global_identity(@bob)

    workspace_post "/join/INVALID_CODE", workspace: @workspace, params: with_turnstile_response({})

    assert_response :redirect
    assert_match /not valid/, flash[:alert]
  end

  test "submit join form with expired code redirects with alert" do
    sign_in_global_identity(@bob)

    # Expire the join code
    @join_code.update!(expires_at: 1.day.ago)

    workspace_post "/join/#{@join_code.code}", workspace: @workspace, params: with_turnstile_response({})

    assert_response :redirect
    assert_match /expired/, flash[:alert]
  end

  # ============================================================================
  # Transaction rollback when join code redemption fails
  # ============================================================================

  test "exhausted join code redirects with alert and does not create membership" do
    sign_in_global_identity(@bob)

    # Make the join code exhausted (can't be redeemed)
    @join_code.update!(usage_limit: 1, usage_count: 1)

    initial_membership_count = WorkspaceMembership.count

    workspace_post "/join/#{@join_code.code}", workspace: @workspace, params: with_turnstile_response({})

    # Exhausted codes are treated as inactive and redirect with alert
    assert_response :redirect
    assert_match /expired/, flash[:alert]

    # Membership should not have been created
    assert_equal initial_membership_count, WorkspaceMembership.count

    # User should not exist in workspace
    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      user = User.find_by(email_address: "bob@example.com")
      assert_nil user
    end
  end

  # ============================================================================
  # return_to URL preservation
  # ============================================================================

  test "return_to URL preserved through sign-in flow" do
    # Start at join page while signed out
    workspace_get "/join/#{@join_code.code}", workspace: @workspace

    # Sign-in link should exist and have return_to parameter
    assert_select "a[href^='/session/new'][href*='return_to']", minimum: 1
  end

  private

    def setup_workspace_with_join_code(workspace)
      tenant_id = workspace.external_id.to_s

      # Create tenant database if needed
      unless ApplicationRecord.tenant_exist?(tenant_id)
        ApplicationRecord.create_tenant(tenant_id)
      end

      ApplicationRecord.with_tenant(tenant_id) do
        # Create Account (singleton)
        account = Account.find_or_create_by!(singleton_guard: 0) do |a|
          a.name = workspace.name
        end

        # Create admin user for workspace creator
        admin_membership = workspace.creator.workspace_memberships.find_by(tenant: tenant_id)
        if admin_membership
          admin_user = User.find_or_create_by!(email_address: workspace.creator.email_address) do |u|
            u.name = workspace.creator.email_address.split("@").first.titleize
            u.workspace_membership_id = admin_membership.id
            u.role = :administrator
            u.verified_at = Time.current
          end
          admin_membership.update!(user_id: admin_user.id) unless admin_membership.user_id
        end

        # Create join code
        @join_code = account.join_codes.find_or_create_by!(code: "TEST#{workspace.external_id}") do |jc|
          jc.usage_limit = nil  # unlimited
          jc.usage_count = 0
          jc.expires_at = nil   # never expires
        end
      end
    end

    def setup_user_for_membership(membership)
      tenant_id = membership.tenant

      ApplicationRecord.with_tenant(tenant_id) do
        user = User.find_or_create_by!(email_address: membership.global_identity.email_address) do |u|
          u.name = membership.global_identity.email_address.split("@").first.titleize
          u.workspace_membership_id = membership.id
          u.role = :member
          u.verified_at = Time.current
        end
        membership.update!(user_id: user.id) unless membership.user_id
      end
    end
end
