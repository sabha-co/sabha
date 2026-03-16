# frozen_string_literal: true

require_relative "../../test_helper"

class ApplicationCable::SaasConnectionTest < ActionCable::Connection::TestCase
  include SaasTestHelper

  tests ApplicationCable::Connection

  # Note: ActionCable connection tests require manually setting up the tenant context
  # since the middleware doesn't run. We simulate this by setting env vars that
  # the gem's CableConnection::Base expects.

  test "connects with valid global_session_token and workspace membership" do
    session = global_sessions(:alice_session)
    workspace = workspaces(:acme)

    # Set the signed cookie (global_session_token for SaaS mode)
    cookies.signed[:global_session_token] = session.token

    # Simulate the tenant being set by the gem's middleware
    # The gem reads from env["sabha.workspace_id"] or uses tenant_resolver
    connect env: {
      "SCRIPT_NAME" => "/#{workspace.external_id}",
      "sabha.workspace_id" => workspace.external_id.to_s
    }

    assert_equal workspace.external_id.to_s, connection.current_tenant
    assert connection.current_user.present?
  end

  test "rejects connection without global_session_token cookie" do
    workspace = workspaces(:acme)

    assert_reject_connection do
      connect env: {
        "SCRIPT_NAME" => "/#{workspace.external_id}",
        "sabha.workspace_id" => workspace.external_id.to_s
      }
    end
  end

  test "rejects connection with expired session" do
    session = global_sessions(:expired_session)
    workspace = workspaces(:shared)

    cookies.signed[:global_session_token] = session.token

    assert_reject_connection do
      connect env: {
        "SCRIPT_NAME" => "/#{workspace.external_id}",
        "sabha.workspace_id" => workspace.external_id.to_s
      }
    end
  end

  test "rejects connection without workspace membership" do
    # Alice has session but no membership in widgets workspace (bob's workspace)
    session = global_sessions(:alice_session)
    workspace = workspaces(:widgets)

    cookies.signed[:global_session_token] = session.token

    assert_reject_connection do
      connect env: {
        "SCRIPT_NAME" => "/#{workspace.external_id}",
        "sabha.workspace_id" => workspace.external_id.to_s
      }
    end
  end

  test "rejects connection without tenant context" do
    session = global_sessions(:alice_session)

    cookies.signed[:global_session_token] = session.token

    # No tenant in environment - should reject
    assert_reject_connection do
      connect env: { "SCRIPT_NAME" => "" }
    end
  end

  test "connects to workspace where user has membership" do
    # Alice has membership in shared workspace
    session = global_sessions(:alice_session)
    workspace = workspaces(:shared)
    membership = workspace_memberships(:alice_shared)

    # Ensure tenant database exists and has a user
    tenant_id = workspace.external_id.to_s
    ApplicationRecord.create_tenant(tenant_id) unless ApplicationRecord.tenant_exist?(tenant_id)

    ApplicationRecord.with_tenant(tenant_id) do
      user = User.find_or_create_by!(email_address: session.global_identity.email_address) do |u|
        u.name = "Alice"
        u.workspace_membership_id = membership.id
        u.role = :member
        u.verified_at = Time.current
      end
      membership.update!(user_id: user.id) unless membership.user_id == user.id
    end

    cookies.signed[:global_session_token] = session.token

    connect env: {
      "SCRIPT_NAME" => "/#{workspace.external_id}",
      "sabha.workspace_id" => workspace.external_id.to_s
    }

    assert_equal workspace.external_id.to_s, connection.current_tenant
    assert connection.current_user.present?
  end

  test "lazily creates user on first connection when membership exists but user_id is nil" do
    with_provisioned_workspace(name: "Lazy Create Test", creator: global_identities(:alice)) do |workspace|
      bob_membership = WorkspaceMembership.create!(
        global_identity: global_identities(:bob),
        tenant: workspace.external_id.to_s
      )

      session = global_sessions(:bob_session)
      cookies.signed[:global_session_token] = session.token

      connect env: {
        "SCRIPT_NAME" => "/#{workspace.external_id}",
        "sabha.workspace_id" => workspace.external_id.to_s
      }

      assert connection.current_user.present?
      assert_equal "bob@example.com", connection.current_user.email_address

      bob_membership.reload
      assert_not_nil bob_membership.user_id
    end
  end

  test "rejects connection for deactivated user" do
    with_provisioned_workspace(name: "Deactivated User Test", creator: global_identities(:alice)) do |workspace|
      bob_membership = WorkspaceMembership.create!(
        global_identity: global_identities(:bob),
        tenant: workspace.external_id.to_s
      )
      bob_membership.create_user!(role: :member)

      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        User.find(bob_membership.user_id).deactivate
      end

      session = global_sessions(:bob_session)
      cookies.signed[:global_session_token] = session.token

      assert_reject_connection do
        connect env: {
          "SCRIPT_NAME" => "/#{workspace.external_id}",
          "sabha.workspace_id" => workspace.external_id.to_s
        }
      end
    end
  end

  test "rejects connection for banned user" do
    with_provisioned_workspace(name: "Banned User Test", creator: global_identities(:alice)) do |workspace|
      bob_membership = WorkspaceMembership.create!(
        global_identity: global_identities(:bob),
        tenant: workspace.external_id.to_s
      )
      bob_membership.create_user!(role: :member)

      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        User.find(bob_membership.user_id).update!(status: :banned)
      end

      session = global_sessions(:bob_session)
      cookies.signed[:global_session_token] = session.token

      assert_reject_connection do
        connect env: {
          "SCRIPT_NAME" => "/#{workspace.external_id}",
          "sabha.workspace_id" => workspace.external_id.to_s
        }
      end
    end
  end
end
