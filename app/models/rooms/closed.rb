# Rooms where only a subset of all users on the account have been explicited granted membership.
class Rooms::Closed < Room
  def applicable_activity_types(message)
    types = [ :everyone_room_message ]
    types << :mention if message.mentionees.any?
    types
  end
end
