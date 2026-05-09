# Rooms open to all users on the account. Anyone can discover and join via Browse.
# When `auto_join`, all existing users are auto-added and new signups are auto-joined.
class Rooms::Open < Room
  scope :browsable_by, ->(user) {
    active.where.not(id: user.memberships.visible.select(:room_id))
  }

  after_save_commit :grant_access_to_all_users, if: :auto_join?

  def applicable_activity_types(message)
    types = [ :everyone_room_message ]
    types << :mention if message.mentions_everyone? || message.mentionees.any?
    types
  end

  private
    def grant_access_to_all_users
      return unless type_previously_changed?(to: "Rooms::Open") || saved_change_to_auto_join?(to: true)

      users_to_add = User.active
                         .joins("LEFT JOIN memberships ON memberships.user_id = users.id AND memberships.room_id = #{id} AND memberships.active = true")
                         .where("memberships.id IS NULL")

      memberships.grant_to(users_to_add) if users_to_add.exists?
    end
end
