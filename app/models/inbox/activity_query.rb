# Fetches notifications for the user's Activity tab:
# @mentions, boost reactions, and thread replies.
class Inbox::ActivityQuery
  def initialize(user, cleared_at: nil)
    @user = user
    @cleared_at = cleared_at
  end

  def call
    scope = Notification.where(user: user)
                        .with_message_and_creator
                        .ordered

    if (time = cleared_at_time)
      scope = scope.where("notifications.created_at > ?", time)
    end

    scope
  end

  private

  attr_reader :user, :cleared_at

  def cleared_at_time
    return unless cleared_at.present?

    Time.iso8601(cleared_at)
  end
end
