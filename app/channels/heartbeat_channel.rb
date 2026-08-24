class HeartbeatChannel < ApplicationCable::Channel
  # Idleness rides here rather than on PresenceChannel because that one is bound
  # to a room and rejects without one — it would stop hearing from anyone reading
  # their settings. This channel is per-user and already subscribed app-wide as
  # the connection-liveness proxy, so it sees every page.
  #
  # The client reports edges, not a stream: "I stopped" once, "I'm back" once.
  # Rebroadcasting is gated on the state actually changing, so a returning tab
  # that was never really away says nothing.
  def activity(data)
    with_tenant_context do
      return unless current_user

      data["active"] == false ? current_user.went_idle : current_user.interacted
    end
  end
end
