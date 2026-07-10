Rails.application.configure do
  config.x.everyone_mention = ActiveSupport::OrderedOptions.new

  # Above this active-member count, @everyone stops fanning out per-member
  # notifications (push, missed-email bundles, and the per-recipient live
  # activity/badge broadcasts) and posts room-wide instead. The durable
  # Activity-tab rows and the mention badge are still written.
  config.x.everyone_mention.ceiling =
    ENV.fetch("EVERYONE_MENTION_CEILING", 1000).to_i

  # At or above this active-member count, the composer asks the sender to
  # confirm @everyone before sending, showing the real recipient count.
  config.x.everyone_mention.confirm_threshold =
    ENV.fetch("EVERYONE_MENTION_CONFIRM_THRESHOLD", 15).to_i
end
