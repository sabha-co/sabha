# Rooms for direct message chats between users. These act as a singleton, so a single set of users will
# always refer to the same direct room.
class Rooms::Direct < Room
  class BlankMessageError < StandardError; end

  after_create_commit :broadcast_to_sidebar
  after_create_commit :ensure_members_hash

  class << self
    # A conversation exists only once someone sends something, so opening the
    # compose surface (Rooms::DirectsController#new) writes nothing — this finder
    # resolves the existing DM for a user set without creating one, and also
    # covers the stale-link case where a cached "Message X" link is followed after
    # the DM already exists.
    def for(users)
      find_by(members_hash: members_hash_for(users))
    end

    def find_or_create_for(users)
      hash = members_hash_for(users)
      find_by(members_hash: hash) || create_racing(users, hash)
    end

    # Materializes the DM lazily, on its first message, and returns that message: a
    # DM only exists once someone actually sends something, so opening the compose
    # surface writes nothing (see Rooms::DirectsController#new) and never prepends
    # an empty conversation into the recipient's sidebar. Room + first message live
    # in one transaction so a blank first send rolls back a *just-created* DM rather
    # than leaving an empty room behind — a DM that already existed is left intact,
    # we simply don't add the invalid message to it.
    def message_to(users, creator:, message_params:)
      transaction do
        room = find_or_create_for(users)
        message = room.messages.create_with_attachment!(message_params.merge(creator: creator))

        # Messages carry no body-presence validation, so a blank body with no
        # attachment would otherwise leave an empty DM behind — the exact thing
        # lazy materialization exists to prevent. Roll the just-opened DM back.
        raise BlankMessageError if message.plain_text_body.blank?

        message
      end
    end

    def members_hash_for(users)
      Digest::MD5.hexdigest(users.map(&:id).sort.join(","))
    end

    private
      # The create branch of find_or_create_for, isolated in a savepoint
      # (requires_new) so a lost race on the unique members_hash index rolls back
      # only this attempt. Without the savepoint, create_for's transaction would
      # join an enclosing one (message_to's) and — on PostgreSQL — the failed
      # INSERT would abort that whole transaction, so the recovering find_by! would
      # raise InFailedSqlTransaction instead of returning the row the winner created.
      def create_racing(users, hash)
        transaction(requires_new: true) do
          create_for({ members_hash: hash }, users: users)
        end
      rescue ActiveRecord::RecordNotUnique
        find_by!(members_hash: hash)
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

  # Returns users in this DM room excluding the given user, with avatars eager loaded
  def members_for_display(excluding:)
    memberships.active
      .includes(user: { avatar_attachment: { blob: :variant_records } })
      .map(&:user)
      .reject { |u| u.id == excluding.id }
  end

  # Batch load members for multiple rooms, returning { room_id => [users] }
  # Excludes the given user from each room's member list
  def self.members_for_display_by_room(room_ids, excluding:)
    return {} if room_ids.empty?

    Membership.active
      .where(room_id: room_ids)
      .includes(user: { avatar_attachment: { blob: :variant_records } })
      .group_by(&:room_id)
      .transform_values { |ms| ms.map(&:user).reject { |u| u.id == excluding.id } }
  end

  def compute_members_hash
    self.class.members_hash_for(users)
  end

  def applicable_activity_types(message)
    types = [ :direct_message ]
    types << :mention if message.mentionees.any?
    types
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
