# Resolving access to a nested sub-channel (a chat thread or a forum post), whose
# access derives from its parent rather than a per-sub-channel membership. A member
# can open one without a row of their own, and a silenced-but-active row must not
# keep granting access after they lose parent access. Shared by the controllers
# that resolve a channel from params (channels, messages, the @mention picker).
module SubChannelAccessible
  extend ActiveSupport::Concern

  private
    # A sub-channel resolved by id, but only if the user can currently view it.
    def viewable_sub_channel(channel_id)
      channel = Channel.active.sub_channels.find_by(id: channel_id)
      channel if channel&.viewable_by?(Current.user)
    end

    # Drops a sub-channel resolved via a stale membership: re-check derived access so
    # a member removed from the parent loses it immediately rather than riding an
    # orphaned row. A non-sub-channel (a normal sidebar channel) passes through untouched.
    def deny_stale_sub_channel(channel)
      channel unless channel&.stale_sub_channel_for?(Current.user)
    end
end
