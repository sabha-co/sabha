# frozen_string_literal: true

require_relative "../test_helper"

class SaasRoomChannelTest < ActionCable::Channel::TestCase
  tests RoomChannel

  # Note: Channel tests stub the connection. In SaaS mode, we need to
  # set up tenant context and create workspace-scoped test data.

  setup do
    @workspace = workspaces(:acme)
    @membership = workspace_memberships(:alice_acme)

    # Create tenant database and test data
    with_tenant_database(@workspace) do
      # Create user linked to the workspace membership
      @user = User.find_or_create_by!(email_address: "alice@example.com") do |u|
        u.name = "Alice"
        u.workspace_membership_id = @membership.id
        u.role = :administrator
        u.verified_at = Time.current
      end

      # Update membership with user_id cache
      @membership.update!(user_id: @user.id) unless @membership.user_id == @user.id

      # Create a room for testing
      @room = Rooms::Open.find_or_create_by!(name: "General") do |r|
        r.slug = "general"
        r.creator = @user
      end

      # Create membership in room
      @room.memberships.find_or_create_by!(user: @user)
    end

    # Stub connection with tenant context
    stub_connection(
      current_user: @user,
      current_tenant: @workspace.external_id.to_s
    )
  end

  test "subscribes to a room the user is a member of" do
    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      subscribe room_id: @room.id

      assert subscription.confirmed?
      assert_has_stream_for @room
    end
  end

  test "rejects subscription to room user is not a member of" do
    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      # Create a closed room that alice is not a member of
      other_room = Rooms::Closed.create!(
        name: "Secret Room",
        creator: @user
      )
      # Remove alice's auto-created membership
      other_room.memberships.where(user: @user).delete_all

      subscribe room_id: other_room.id

      assert subscription.rejected?
    end
  end

  test "rejects subscription without room_id" do
    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      subscribe

      assert subscription.rejected?
    end
  end

  test "rejects subscription with invalid room_id" do
    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      subscribe room_id: -1

      assert subscription.rejected?
    end
  end

  test "rejects subscription to non-existent room ID in current tenant" do
    # Use a room ID that doesn't exist in this tenant (even if it exists in another)
    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      subscribe room_id: 999999
      assert subscription.rejected?
    end
  end
end
