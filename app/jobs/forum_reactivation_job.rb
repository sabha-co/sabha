class ForumReactivationJob < ApplicationJob
  queue_as :default

  rescue_from ActiveJob::DeserializationError do
  end

  # Restores the posts a forum's deletion cascaded — and only those, so a post
  # deleted on its own stays deleted. Rooms::Forum#reactivate brings the
  # forum row + memberships back synchronously; this restores each post's
  # messages and memberships in its own short transaction (Room::Nested), so the
  # write lock is released between posts. Idempotent: a retry re-scans and skips
  # posts already restored (no longer active: false + cascade_deactivated).
  #
  # The forum's own `active` flag is the (de)activation state: if a re-deletion
  # supersedes this restore — before the job starts or mid-cascade — stop so the
  # two never interleave, then hand off to ForumDeactivationJob to re-delete. The
  # pair converge on the forum's final state, so the last admin action wins even
  # under concurrent workers.
  def perform(forum:)
    return unless forum.active?

    Rooms::Post.where(parent_room_id: forum.id, active: false, cascade_deactivated: true).in_batches do |batch|
      break unless forum.reload.active?
      batch.each(&:reactivate)
    end

    ForumDeactivationJob.perform_later(forum: forum) unless forum.reload.active?
  end
end
