# Fetches messages where the user was @mentioned, mentioned via @everyone, or received as a direct message.
class Inbox::MentionsQuery
  def initialize(user)
    @user = user
  end

  def call
    user.mentioning_messages
        .without_created_by(user)
        .with_thread_summary
        .with_creator
  end

  private

  attr_reader :user
end
