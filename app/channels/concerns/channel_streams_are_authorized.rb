# Prepended onto Turbo::StreamsChannel. The subscriber names the channel it wants
# in the subscribe frame, so authorizing channel streams only in ChannelStreamsChannel
# would leave the stock channel as the way around it: same signed stream name, no
# access check. Turn those names away here and ChannelStreamsChannel becomes the
# only door. Every other stream — the sidebar, the inbox, a membership — is
# already bound to the user or the account and passes straight through.
module ChannelStreamsAreAuthorized
  def subscribed
    if ChannelStreamsChannel.guarded_stream?(verified_stream_name_from_params)
      reject
    else
      super
    end
  end
end
