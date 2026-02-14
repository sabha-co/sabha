# Fetches messages where the user was @mentioned or mentioned via @everyone.
# DMs are excluded - they have their own inbox view.
class Inbox::ActivityQuery
  def initialize(user)
    @user = user
  end

  def call
    user.mentioning_messages
        .without_events
        .without_created_by(user)
        .where.not(rooms: { type: "Rooms::Direct" })
        .with_thread_summary
        .with_creator
  end

  private

  attr_reader :user
end
