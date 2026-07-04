# Rooms open to all users on the account. Anyone can discover and join via Browse.
# When `auto_join`, all existing users are auto-added and new signups are auto-joined.
class Rooms::Open < Room
  include Room::AutoJoinable

  def applicable_activity_types(message)
    types = [ :everyone_room_message ]
    types << :mention if message.mentions_everyone? || message.mentionees.any?
    types
  end
end
