# frozen_string_literal: true

require_relative "../test_helper"

class SaasRoomListChannelTest < ActionCable::Channel::TestCase
  include SaasTestHelper

  tests RoomListChannel

  test "two workspaces' room-list streams do not collide" do
    with_provisioned_workspace(name: "Stream WS A", creator: global_identities(:alice)) do |ws_a|
      with_provisioned_workspace(name: "Stream WS B", creator: global_identities(:bob)) do |ws_b|
        stream_a = ApplicationRecord.with_tenant(ws_a.external_id.to_s) { RoomListChannel.broadcasting_for(Account.sole) }
        stream_b = ApplicationRecord.with_tenant(ws_b.external_id.to_s) { RoomListChannel.broadcasting_for(Account.sole) }

        assert_not_equal stream_a, stream_b

        # The stream identity is the account's GlobalID, which carries the
        # tenant — a room-touched nudge in one workspace can never reach
        # another workspace's sidebars.
        [ [ stream_a, ws_a ], [ stream_b, ws_b ] ].each do |stream, workspace|
          gid = GlobalID.parse(stream.delete_prefix("room_list:"))
          assert_equal workspace.external_id.to_s, gid.tenant
        end
      end
    end
  end
end
