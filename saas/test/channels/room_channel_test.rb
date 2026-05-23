# frozen_string_literal: true

require_relative "../test_helper"

class SaasRoomChannelTest < ActionCable::Channel::TestCase
  tests RoomChannel

  setup do
    @workspace = Workspace.create_with_database!(
      name: "Channel Test",
      creator: global_identities(:alice)
    )
    @membership = global_identities(:alice).workspace_memberships.find_by(tenant: @workspace.external_id.to_s)
    @user = @membership.user

    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      @room = Rooms::Open.find_by(name: "General")
      @room.memberships.find_or_create_by!(user: @user)
    end

    stub_connection(
      current_user: @user,
      current_tenant: @workspace.external_id.to_s
    )
  end

  teardown do
    @workspace&.destroy_with_database! if @workspace && Workspace.exists?(id: @workspace.id)
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
      other_room = Rooms::Closed.create!(
        name: "Secret Room",
        creator: @user
      )
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

  test "rejects subscription to non-existent room ID in current tenant" do
    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      subscribe room_id: 999999
      assert subscription.rejected?
    end
  end
end
