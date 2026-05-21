class Boost < ApplicationRecord
  Group = Data.define(:content, :count, :boosters, :truncated)

  belongs_to :message, touch: true
  belongs_to :booster, class_name: "User", default: -> { Current.user }

  validates :content, uniqueness: { scope: [ :message_id, :booster_id ] }

  scope :ordered, -> { order(:created_at) }

  after_create_commit :broadcast_create
  after_create_commit :dispatch_boost_notification
  before_destroy :delete_notification
  after_destroy_commit :broadcast_removal
  after_destroy_commit :broadcast_notification_removal

  private
    def broadcast_create
      targets = "[id='#{boosts_target}']"
      rendering = { partial: "messages/boosts/boost", locals: { boost: self } }

      Turbo::StreamsChannel.broadcast_action_to(message.room, :messages, action: :append, targets: targets, **rendering)
      Turbo::StreamsChannel.broadcast_action_to(Current.account, :inbox, action: :append, targets: targets, **rendering)
    end

    def dispatch_boost_notification
      return if message.creator_id == booster_id
      return if message.room.direct? || message.room.parent_room&.direct?

      Notification::DispatchJob.perform_later(message, only: :boost, actor: booster)
    end

    def delete_notification
      notification = Notification.find_by(boost_id: id)
      return unless notification

      @destroyed_notification = {
        user: notification.user,
        dom_id: ActionView::RecordIdentifier.dom_id(notification),
        message_id: notification.message_id
      }

      notification.destroy!
    end

    def broadcast_notification_removal
      return unless @destroyed_notification

      Turbo::StreamsChannel.broadcast_remove_to(
        [ @destroyed_notification[:user], :inbox_activity ],
        target: @destroyed_notification[:dom_id]
      )

      Notification::BoostGroup.broadcast_update_after_removal(
        user: @destroyed_notification[:user],
        message_id: @destroyed_notification[:message_id]
      )

      @destroyed_notification[:user].broadcast_activity_indicator
    end

    def broadcast_removal
      targets = "[id='boost_#{id}']"

      Turbo::StreamsChannel.broadcast_action_to(message.room, :messages, action: :remove, targets: targets)
      Turbo::StreamsChannel.broadcast_action_to(Current.account, :inbox, action: :remove, targets: targets)
    end

    def boosts_target
      "boosts_message_#{message.client_message_id}"
    end
end
