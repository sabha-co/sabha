# Fetches messages from channels the user has access to, filtered by membership involvement level (:visible or :notifications_on).
class Inbox::MessagesQuery
  INVOLVEMENT_SCOPES = %i[visible notifications_on].freeze

  def initialize(user, involvement: :visible)
    @user = user
    @involvement = involvement

    validate_involvement!
  end

  def call
    Message.active
           .in_channels(involved_channel_ids)
           .without_events
           .without_created_by(user)
           .for_display
  end

  private

  attr_reader :user, :involvement

  # Channels where the user's own membership carries the requested involvement. The
  # inbox surfaces messages by YOUR involvement, so it's membership-based — not
  # the derived reach of User#reachable_messages (a member who can merely *view* a
  # sub-channel, without an involved membership, gets no inbox entry for it).
  def involved_channel_ids
    user.memberships.active.public_send(involvement).select(:channel_id)
  end

  def validate_involvement!
    return if INVOLVEMENT_SCOPES.include?(involvement)

    raise ArgumentError, "Invalid involvement: #{involvement}. Must be one of: #{INVOLVEMENT_SCOPES.join(', ')}"
  end
end
