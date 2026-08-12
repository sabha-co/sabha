# Fetches notifications for the user's Activity tab:
# @mentions, boost reactions, and thread replies. An optional filter — the tab
# the reader picked — narrows to a single activity type.
class Inbox::ActivityQuery
  # Filter tab (URL value) → the activity_type it isolates. Absent or unknown
  # values fall through to the unfiltered feed.
  FILTERS = { "mentions" => "mention", "replies" => "thread_reply", "reactions" => "boost" }.freeze

  def initialize(user, filter: nil)
    @user = user
    @filter = filter
  end

  def call
    scope = Notification.where(user: user).with_message_and_creator.ordered
    activity_type = FILTERS[@filter]
    activity_type ? scope.where(activity_type: activity_type) : scope
  end

  private

  attr_reader :user
end
