# Follow state shared by nested sub-rooms — Rooms::Post (a forum post) and
# Rooms::Thread (a chat thread). Access to a sub-room derives from its parent
# (see each type's #viewable_by?), so a membership row here is pure subscription
# state: it decides who hears about replies, not who can open the room. A member
# becomes a follower lazily — the moment they reply (Message::Threadable) or
# explicitly Follow — so a sub-room never fans a membership row out to every
# parent member. Mirrors Fizzy's Watch created on comment.
module Room::Followable
  extend ActiveSupport::Concern

  # True when the user is a follower — an active, non-invisible membership that
  # drives reply notifications. The author and anyone who replied or explicitly
  # Followed qualifies; a member who never engaged (access is parent-derived) does
  # not.
  def followed_by?(user)
    user.present? && memberships.active.where.not(involvement: "invisible").exists?(user_id: user.id)
  end

  # Who hears about a reply here: this sub-room's followers (active, non-invisible
  # members) unioned with the parent room's "everything" members, minus the
  # excluded user (the reply's author). Both CreateThreadReplyNotificationsJob and
  # BroadcastInboxThreadsJob deliver to exactly this set.
  def reply_recipient_ids(excluding:)
    follower_ids = memberships.active.visible.pluck(:user_id)
    everything_ids = parent_room.memberships.active.involved_in_everything.pluck(:user_id)
    (follower_ids + everything_ids).uniq - Array(excluding)
  end

  # A member becomes a follower the moment they reply — lazily, so a sub-room
  # never fans a membership row out to every member. Idempotent and self-healing:
  # it (re)activates a dropped membership and lifts an invisible one back to
  # "everything", but never downgrades a follower who dialed themselves down.
  def follow!(user)
    membership = Membership.find_or_initialize_by(room_id: id, user_id: user.id)
    membership.active = true
    membership.involvement = "everything" if membership.new_record? || membership.involved_in_invisible?
    membership.save! if membership.changed?
    membership
  end

  def unfollow!(user)
    Membership.where(room_id: id, user_id: user.id).destroy_all
  end
end
