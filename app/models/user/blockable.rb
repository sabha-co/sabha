module User::Blockable
  extend ActiveSupport::Concern

  included do
    has_many :blocks_given, class_name: "Block", foreign_key: :blocker_id, dependent: :destroy
    has_many :blocked_users, through: :blocks_given, source: :blocked

    has_many :blocks_received, class_name: "Block", foreign_key: :blocked_id, dependent: :destroy
    has_many :blocked_by_users, through: :blocks_received, source: :blocker
  end

  def blocked_in?(room)
    return false unless room.one_on_one?

    !can_ping?(room.roommate_to(self))
  end

  def can_ping?(other_user)
    !blocked?(other_user) && !blocked_by?(other_user)
  end

  def can_direct_message?(other_user)
    other_user&.active? &&
      can_ping?(other_user) &&
      can_create_direct_messages?
  end

  def blocked?(other_user)
    blocked_users.exists?(other_user&.id)
  end

  def blocked_by?(other_user)
    blocked_by_users.exists?(other_user&.id)
  end

  def block!(other_user)
    block = blocks_given.find_or_create_by!(blocked: other_user)
    dm_room_with(other_user)&.post_system_message(event: "user_blocked", body: "blocked #{other_user.name}", actor: self) if block.previously_new_record?
  end

  def unblock!(other_user)
    count = blocks_given.where(blocked: other_user).delete_all
    dm_room_with(other_user)&.post_system_message(event: "user_unblocked", body: "unblocked #{other_user.name}", actor: self) if count > 0
  end

  private
    def dm_room_with(other_user)
      Rooms::Direct.find_by(members_hash: Rooms::Direct.members_hash_for(User.where(id: [ id, other_user.id ])))
    end
end
