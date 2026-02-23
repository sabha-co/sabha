# Fetches notifications for the user's Activity tab:
# @mentions, boost reactions, and thread replies.
class Inbox::ActivityQuery
  def initialize(user)
    @user = user
  end

  def call
    Notification.where(user: user)
                .with_message_and_creator
                .ordered
  end

  private

  attr_reader :user
end
