# frozen_string_literal: true

require_relative "../test_helper"

class SaasChannelScopedChannelTest < ActionCable::Channel::TestCase
  tests ChannelScopedChannel

  setup do
    @workspace = Workspace.create_with_database!(
      name: "Channel Test",
      creator: global_identities(:alice)
    )
    @membership = global_identities(:alice).workspace_memberships.find_by(tenant: @workspace.external_id.to_s)
    @user = @membership.user

    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      @channel = Channels::Open.find_by(name: "General")
      @channel.memberships.grant_to(@user)
    end

    stub_connection(
      current_user: @user,
      current_tenant: @workspace.external_id.to_s
    )
  end

  teardown do
    @workspace&.destroy_with_database! if @workspace && Workspace.exists?(id: @workspace.id)
  end

  test "subscribes to a channel the user is a member of" do
    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      subscribe channel_id: @channel.id

      assert subscription.confirmed?
      assert_has_stream_for @channel
    end
  end

  test "rejects subscription to channel user is not a member of" do
    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      other_channel = Channels::Closed.create!(
        name: "Secret Channel",
        creator: @user
      )
      other_channel.memberships.where(user: @user).delete_all

      subscribe channel_id: other_channel.id

      assert subscription.rejected?
    end
  end

  test "rejects subscription without channel_id" do
    ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
      subscribe

      assert subscription.rejected?
    end
  end
end
