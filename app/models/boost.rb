class Boost < ApplicationRecord
  include Deactivatable

  belongs_to :message, touch: true
  belongs_to :booster, class_name: "User", default: -> { Current.user }

  validates :content, uniqueness: { scope: [ :message_id, :booster_id ], conditions: -> { active } }

  scope :ordered, -> { order(:created_at) }

  after_create_commit :broadcast_create
  after_create_commit :create_boost_notification
  after_update_commit :broadcast_reactivation, if: -> { saved_change_to_attribute?(:active) && active? }
  after_update_commit :broadcast_deactivation, if: -> { saved_change_to_attribute?(:active) && !active? }
  after_update_commit :destroy_boost_notification, if: -> { saved_change_to_attribute?(:active) && !active? }

  private
    def broadcast_create
      broadcast_append_to message.room, :messages, target: boosts_target, partial: "messages/boosts/boost", locals: { boost: self }
      broadcast_append_to :inbox, target: boosts_target, partial: "messages/boosts/boost", locals: { boost: self }
    end

    def create_boost_notification
      return if message.creator_id == booster_id
      return if message.room.direct? || message.room.parent_room&.direct?

      notification = Notification.create!(
        user_id: message.creator_id,
        message_id: message_id,
        actor_id: booster_id,
        activity_type: "boost",
        boost_id: id
      )

      Turbo::StreamsChannel.broadcast_append_to(
        [ notification.user, :inbox_activity ],
        target: "inbox",
        partial: "notifications/notification",
        locals: { notification: notification, timestamp_style: :long_datetime }
      )
    end

    def destroy_boost_notification
      notification = Notification.find_by(boost_id: id)
      return unless notification

      user = notification.user
      notification_dom_id = ActionView::RecordIdentifier.dom_id(notification)

      notification.destroy!

      Turbo::StreamsChannel.broadcast_remove_to(
        [ user, :inbox_activity ],
        target: notification_dom_id
      )

      Notification::BoostGroup.broadcast_update_after_removal(user: user, message_id: notification.message_id)
    end

    def broadcast_deactivation
      broadcast_remove_to message.room, :messages
      broadcast_remove_to :inbox
    end

    def boosts_target
      "boosts_message_#{message.client_message_id}"
    end

    def broadcast_reactivation
      previous_boost = message.boosts.where("created_at < ?", created_at).last

      if previous_boost.present?
        target = previous_boost
        action = "after"
      else
        target = [ message.room, :messages ]
        action = "prepend"
      end

      broadcast_action_to message.room, :messages,
                          action:,
                          target:,
                          partial: "messages/boosts/boost",
                          locals: { boost: self }
    end
end
