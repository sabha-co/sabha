class ChannelScopedChannel < ApplicationCable::Channel
  def subscribed
    if channel
      stream_for channel
    else
      reject
    end
  end

  private
    # Memoized for the length of one command, never across them. Every command
    # arrives as its own RPC with a fresh channel object, so the next one resolves
    # the channel again — and re-checks access while it's there, which is why holding
    # it wouldn't be an improvement. AnyCable/InstanceVars can't tell the two
    # apart, so the exemption is here rather than on the whole file.
    def channel
      @channel ||= find_channel # rubocop:disable AnyCable/InstanceVars
    end

    def find_channel
      with_tenant_context do
        # A sub-channel (forum post or chat thread) derives access from its parent, so
        # a parent member reaches it (typing, presence) without a per-sub-channel
        # membership — and a stale, silenced-but-active row can't keep granting it
        # after they lose parent access. An outsider resolves nil and is rejected.
        current_user&.reachable_channel(params[:channel_id])
      end
    end
end
