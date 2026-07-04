class ForumDeactivationJob < ApplicationJob
  queue_as :default

  rescue_from ActiveJob::DeserializationError do
  end

  # Soft-deletes a deleted forum's posts — their messages, memberships, and
  # notifications — off the request path. Rooms::Forum#deactivate cuts access
  # synchronously (forum row + memberships); this handles the O(posts × replies)
  # cascade. Each post deactivates in its own short transaction (Room::Nested),
  # so SQLite's single-writer lock is released between posts rather than held for
  # the whole forum.
  #
  # Only still-active posts are cascaded, so a post deleted on its own keeps its
  # non-cascade marker and stays deleted across a forum restore (R15). Idempotent:
  # a retry re-scans and simply skips the now-inactive posts, so re-running from
  # the start is safe.
  #
  # The forum's own `active` flag is the (de)activation state: if a reactivation
  # supersedes this delete — before the job starts or mid-cascade — bail so the
  # two never interleave. Any posts already soft-deleted are picked back up by
  # ForumReactivationJob, so the reactivation wins cleanly.
  def perform(forum:)
    return if forum.active?

    Rooms::Post.active.where(parent_room_id: forum.id).in_batches do |batch|
      return if forum.reload.active?
      batch.each { |post| post.deactivate(cascade: true) }
    end
  end
end
