class Push::Subscription < ApplicationRecord
  belongs_to :user

  def notification(**params)
    WebPush::Notification.new(**params, badge: user.memberships.unread.select(&:has_unread_notifications?).count, endpoint: endpoint, p256dh_key: p256dh_key, auth_key: auth_key)
  end
end
