Rails.application.config.to_prepare do
  Turbo::StreamsChannel.prepend ChannelStreamsAreAuthorized
end
