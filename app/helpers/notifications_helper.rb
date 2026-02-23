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
end
