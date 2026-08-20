class Boost < ApplicationRecord
  Group = Data.define(:content, :count, :boosters, :truncated)

  # How many reactor avatars a grouped chip stacks before collapsing the rest
  # into a trailing "+N".
  AVATARS_SHOWN = 5

  belongs_to :message, touch: true
  belongs_to :booster, class_name: "User", default: -> { Current.user }

  validates :content, uniqueness: { scope: [ :message_id, :booster_id ] }

  scope :ordered, -> { order(:created_at) }

  # One registration for both events: Rails silently drops one of two commit
  # callbacks that share a method name across different events.
  after_commit :broadcast_boosts, on: %i[ create destroy ]
  after_create_commit :dispatch_boost_notification
  before_destroy :delete_notification
  after_destroy_commit :broadcast_notification_removal

  private
    # Reactions render grouped by emoji, so a single boost changing shifts the
    # whole chip row (a new chip, an extra avatar, or a chip disappearing).
    # Replace the entire container rather than append/remove one chip — replace
    # is idempotent, so the author receiving both the direct response and this
    # broadcast just re-renders the same row.
    def broadcast_boosts
      # This commit changed the reactions, so drop any grouping memoized on the
      # message instance before the two stream renders recompute it once.
      message.reset_boost_groups

      targets = "[id='#{boosts_frame_id}']"
      rendering = { partial: "messages/boosts/boosts", locals: { message: message } }

      Turbo::StreamsChannel.broadcast_action_to(message.room, :messages, action: :replace, targets: targets, **rendering)
      Turbo::StreamsChannel.broadcast_action_to(Account.sole, :inbox, action: :replace, targets: targets, **rendering)
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

    # Matches turbo_frame_tag(message, :boosting) — the message dom key is its
    # client_message_id (Message#to_key).
    def boosts_frame_id
      "boosting_message_#{message.client_message_id}"
    end
end
