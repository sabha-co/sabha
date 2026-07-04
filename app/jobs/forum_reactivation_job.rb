class ForumReactivationJob < ApplicationJob
  queue_as :default

  rescue_from ActiveJob::DeserializationError do
  end

  # Restores the posts a forum's deletion cascaded — and only those, so a post
  # deleted on its own stays deleted (R15). Rooms::Forum#reactivate brings the
  # forum row + memberships back synchronously; this restores each post's
  # messages and memberships in its own short transaction (Room::Nested), so the
  # write lock is released between posts. Idempotent: a retry re-scans and skips
  # posts already restored (no longer active: false + cascade_deactivated).
  def perform(forum:)
    Rooms::Post.where(parent_room_id: forum.id, active: false, cascade_deactivated: true).find_each do |post|
      post.reactivate
    end
  end
end
