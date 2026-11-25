# Channels open to all users on the account. Anyone can discover and join via Browse.
# When `auto_join`, all existing users are auto-added and new signups are auto-joined.
class Channels::Open < Channel
  include Channel::AutoJoinable

  def applicable_activity_types(message)
    types = [ :everyone_channel_message ]
    # A capped @everyone drops the :mention pass, so its push (channel.user_ids) and
    # missed-email bundle don't fan out to the whole channel; the message still
    # rides :everyone_channel_message like any other post.
    types << :mention if (message.mentions_everyone? || message.mentionees.any?) && !message.everyone_mention_capped?
    types
  end
end
