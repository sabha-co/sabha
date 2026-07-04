class ForumFollowCleanupJob < ApplicationJob
  queue_as :default

  # Silences a member's post Follows in a forum they left: their per-post
  # memberships go invisible so reply notifications stop. Scoped to that one
  # member — never touches other members' follows, so it stays cheap even in a
  # huge forum. Idempotent: re-running only re-sets already-invisible rows. A
  # later reply re-follows the post via Rooms::Post#follow!, which lifts an
  # invisible membership back to "everything".
  def perform(forum:, user:)
    post_ids = Rooms::Post.where(parent_room_id: forum.id).select(:id)

    Membership.active.where(user_id: user.id, room_id: post_ids)
              .where.not(involvement: "invisible")
              .update_all(involvement: "invisible")
  end
end
