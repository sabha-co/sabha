# frozen_string_literal: true

require_relative "../test_helper"

class SaasPresenceChannelTest < ActionCable::Channel::TestCase
  tests PresenceChannel

  setup do
    @workspace = Workspace.create_with_database!(
      name: "Presence Test",
      creator: global_identities(:alice)
    )
    @membership = global_identities(:alice).workspace_memberships.find_by(tenant: @workspace.external_id.to_s)
    @user = @membership.user

    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      @room = Rooms::Open.find_by(name: "General")
      @room.memberships.grant_to(@user)
    end

    stub_connection(
      current_user: @user,
      current_tenant: @workspace.external_id.to_s
    )
  end

  teardown do
    @workspace&.destroy_with_database! if @workspace && Workspace.exists?(id: @workspace.id)
  end

  test "the presence stream is scoped to the tenant so sets can't collide across workspaces" do
    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      stream = PresenceChannel.broadcasting_for(@room)
      gid = GlobalID.parse(stream.delete_prefix("presence:"))

      assert_equal @workspace.external_id.to_s, gid.tenant
    end
  end

  test "presenting joins the tenant-scoped presence stream" do
    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      subscribe room_id: @room.id

      subscription.expects(:join_presence).with(PresenceChannel.broadcasting_for(@room))
      subscription.present
    end
  end
end
