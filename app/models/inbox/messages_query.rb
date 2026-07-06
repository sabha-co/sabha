# Fetches messages from rooms the user has access to, filtered by membership involvement level (:visible or :notifications_on).
class Inbox::MessagesQuery
  INVOLVEMENT_SCOPES = %i[visible notifications_on].freeze

  def initialize(user, involvement: :visible)
    @user = user
    @involvement = involvement

    validate_involvement!
  end

  def call
    Message.active
           .in_rooms(involved_room_ids)
           .without_events
           .without_created_by(user)
           .for_display
  end

  private

  attr_reader :user, :involvement

  # Rooms where the user's own membership carries the requested involvement. The
  # inbox surfaces messages by YOUR involvement, so it's membership-based — not
  # the derived reach of User#reachable_messages (a member who can merely *view* a
  # sub-room, without an involved membership, gets no inbox entry for it).
  def involved_room_ids
    user.memberships.active.public_send(involvement).select(:room_id)
  end

  def validate_involvement!
    return if INVOLVEMENT_SCOPES.include?(involvement)

    raise ArgumentError, "Invalid involvement: #{involvement}. Must be one of: #{INVOLVEMENT_SCOPES.join(', ')}"
  end
end
