# Rooms for direct message chats between users. These act as a singleton, so a single set of users will
# always refer to the same direct room.
class Rooms::Direct < Room
  class << self
    def find_or_create_for(users)
      find_for(users) || create_for({}, users: users)
    end

    private
      # FIXME: Find a more performant algorithm that won't be a problem on accounts with 10K+ direct rooms,
      # which could be to store the membership id list as a hash on the room, and use that for lookup.
      def find_for(users)
        all.joins(:users).detect do |room|
          Set.new(room.user_ids) == Set.new(users.pluck(:id))
        end
      end
  end

  def default_involvement(user: nil)
    "everything"
  end
end
