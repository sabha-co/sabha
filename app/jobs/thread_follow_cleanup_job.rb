class ThreadFollowCleanupJob < ApplicationJob
  queue_as :default

  # Silences a member's chat-thread follows in a room they left so reply
  # notifications stop. Off the request path because it can span many threads;
  # idempotent, so a retry is safe. A later reply re-involves the member via
  # Room#involve_user, which lifts an invisible membership back to "mentions".
  # Mirrors ForumFollowCleanupJob for a forum's posts.
  def perform(room:, user:)
    room.silence_thread_follows_for(user)
  end
end
