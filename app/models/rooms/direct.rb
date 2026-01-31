# Rooms for direct message chats between users. These act as a singleton, so a single set of users will
# always refer to the same direct room.
class Rooms::Direct < Room
  after_create_commit :broadcast_to_sidebar
  after_create_commit :ensure_members_hash

  class << self
    def find_or_create_for(users)
      hash = members_hash_for(users)
      find_by(members_hash: hash) || create_for({ members_hash: hash }, users: users)
    end

    def members_hash_for(users)
      Digest::MD5.hexdigest(users.map(&:id).sort.join(","))
    end
  end

  def default_involvement(user: nil)
    "everything"
  end

  def one_on_one?
    users.size == 2
  end

  def other_user(for_user: Current.user)
    users.without(for_user).first if one_on_one?
  end

  def compute_members_hash
    self.class.members_hash_for(users)
  end

  private
    def broadcast_to_sidebar
      memberships.each do |membership|
        membership.broadcast_prepend_to membership.user, :rooms,
          target: :direct_rooms,
          partial: "users/sidebars/rooms/direct"
      end
    end

    def ensure_members_hash
      update_column(:members_hash, compute_members_hash) if members_hash.blank?
    end
end
