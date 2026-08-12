module NotificationsHelper
  # Groups consecutive boost notifications on the same message into
  # Notification::BoostGroup presenters. Mentions and thread replies
  # pass through unchanged.
  def group_boost_notifications(notifications)
    notifications.chunk { |n|
      n.boost_notification? ? [ :boost, n.message_id ] : [ :other, n.object_id ]
    }.flat_map { |(_type, _key), group|
      group.first.boost_notification? ? Notification::BoostGroup.new(group) : group
    }
  end

  # The corner-badge glyph for a non-boost activity row. Boosts render through
  # their own grouped partial, so only mentions and replies reach here.
  def activity_glyph(notification)
    notification.mention? ? "@" : "↩"
  end

  # The verb phrase joining the actor to the room ("mentioned you in …"). A
  # reply's room is always a sub-room, so the phrasing splits on thread vs post.
  def activity_verb(notification)
    if notification.mention?
      "mentioned you in"
    elsif notification.message.room.post?
      "replied to a post in"
    else
      "replied in a thread in"
    end
  end

  # The room the row links to: a reply lives in a thread/post sub-room, so we
  # surface its parent (the room or forum the reader recognizes).
  def activity_room(notification)
    room = notification.message.room
    room.sub_room? ? room.parent_room : room
  end
end
