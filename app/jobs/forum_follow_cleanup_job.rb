class ForumFollowCleanupJob < ApplicationJob
  queue_as :default

  # Silences a member's post Follows in a forum they left so reply notifications
  # stop. Off the request path because it can span many posts; idempotent, so a
  # retry is safe. A later reply re-follows the post via Rooms::Post#follow!,
  # which lifts an invisible membership back to "everything".
  def perform(forum:, user:)
    forum.silence_post_follows_for(user)
  end
end
