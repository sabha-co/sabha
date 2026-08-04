# frozen_string_literal: true

require_relative "../test_helper"

# The room is resolved from the stream name's GlobalID, and in SaaS that goes
# through the tenanted locator — so the authorization has to hold up inside a
# tenant, and a name minted in one workspace must not resolve in another.
class SaasRoomStreamsChannelTest < ActionCable::Channel::TestCase
  tests RoomStreamsChannel

  setup do
    @workspace = Workspace.create_with_database!(name: "Streams Test", creator: global_identities(:alice))
    @membership = global_identities(:alice).workspace_memberships.find_by(tenant: @workspace.external_id.to_s)
    @user = @membership.user

    ApplicationRecord.with_tenant(tenant) do
      @room = Rooms::Open.find_by(name: "General")
      @room.memberships.grant_to(@user)
      @signed_stream_name = Turbo::StreamsChannel.signed_stream_name([ @room, :messages ])
    end
  end

  teardown do
    @workspace&.destroy_with_database! if @workspace && Workspace.exists?(id: @workspace.id)
  end

  test "a member subscribes to their room's message stream" do
    stub_connection current_user: @user, current_tenant: tenant

    subscribe signed_stream_name: @signed_stream_name

    assert subscription.confirmed?
  end

  test "a non-member in the same workspace is rejected" do
    outsider = ApplicationRecord.with_tenant(tenant) do
      secret = Rooms::Closed.create!(name: "Secret", creator: @user)
      [ Turbo::StreamsChannel.signed_stream_name([ secret, :messages ]), secret ]
    end

    ApplicationRecord.with_tenant(tenant) { outsider.last.memberships.where(user: @user).delete_all }

    stub_connection current_user: @user, current_tenant: tenant
    subscribe signed_stream_name: outsider.first

    assert subscription.rejected?
  end

  test "a stream name from another workspace does not resolve" do
    other = Workspace.create_with_database!(name: "Other WS", creator: global_identities(:bob))
    other_signed = ApplicationRecord.with_tenant(other.external_id.to_s) do
      Turbo::StreamsChannel.signed_stream_name([ Rooms::Open.find_by(name: "General"), :messages ])
    end

    stub_connection current_user: @user, current_tenant: tenant
    subscribe signed_stream_name: other_signed

    assert subscription.rejected?
  ensure
    other&.destroy_with_database! if other && Workspace.exists?(id: other.id)
  end

  private
    def tenant
      @workspace.external_id.to_s
    end
end
