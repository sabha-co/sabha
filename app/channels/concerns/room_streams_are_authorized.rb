# Prepended onto Turbo::StreamsChannel. The subscriber names the channel it wants
# in the subscribe frame, so authorizing room streams only in RoomStreamsChannel
# would leave the stock channel as the way around it: same signed stream name, no
# access check. Turn those names away here and RoomStreamsChannel becomes the
# only door. Every other stream — the sidebar, the inbox, a membership — is
# already bound to the user or the account and passes straight through.
module RoomStreamsAreAuthorized
  def subscribed
    if RoomStreamsChannel.guarded_stream?(verified_stream_name_from_params)
      reject
    else
      super
    end
  end
end
