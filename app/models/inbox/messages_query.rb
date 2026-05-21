# Fetches messages from rooms the user has access to, filtered by membership involvement level (:visible or :notifications_on).
class Inbox::MessagesQuery
  INVOLVEMENT_SCOPES = %i[visible notifications_on].freeze

  def initialize(user, involvement: :visible)
    @user = user
    @involvement = involvement

    validate_involvement!
  end

  def call
    user.reachable_messages
        .without_events
        .without_created_by(user)
        .for_display
        .merge(Membership.active.public_send(involvement))
  end

  private

  attr_reader :user, :involvement

  def validate_involvement!
    return if INVOLVEMENT_SCOPES.include?(involvement)

    raise ArgumentError, "Invalid involvement: #{involvement}. Must be one of: #{INVOLVEMENT_SCOPES.join(', ')}"
  end
end
