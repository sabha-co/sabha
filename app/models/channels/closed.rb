# Channels where only a subset of all users on the account have been explicited granted membership.
class Channels::Closed < Channel
  def applicable_activity_types(message)
    types = [ :everyone_channel_message ]
    types << :mention if message.mentionees.any?
    types
  end
end
