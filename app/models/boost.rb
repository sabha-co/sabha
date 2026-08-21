class Boost < ApplicationRecord
  Group = Data.define(:content, :count, :boosters, :truncated)

  # How many reactor avatars a grouped chip stacks before collapsing the rest
  # into a trailing "+N".
  AVATARS_SHOWN = 5

  belongs_to :message, touch: true
  belongs_to :booster, class_name: "User", default: -> { Current.user }

  # A boost notifies its message's creator; the row is deleted here (rather than
  # via dependent: :destroy) so the removal can be broadcast after the commit.
  has_many :notifications

  validates :content, uniqueness: { scope: [ :message_id, :booster_id ] }

  scope :ordered, -> { order(:created_at) }

  # One registration for both events: Rails silently drops one of two commit
  # callbacks that share a method name across different events.
  after_commit :broadcast_boosts, on: %i[ create destroy ]
  after_create_commit :dispatch_boost_notification
  before_destroy :delete_notifications
  after_destroy_commit :broadcast_notification_removals

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

    # A boost can have accumulated more than one notification row (racing
    # dispatch jobs), so clear them all — the FK to boosts has no ON DELETE
    # CASCADE, and a leftover row blocks the boost delete with a foreign-key
    # violation. Snapshot each for the removal broadcast before destroying.
    def delete_notifications
      @destroyed_notifications = notifications.map do |notification|
        {
          user: notification.user,
          dom_id: ActionView::RecordIdentifier.dom_id(notification),
          message_id: notification.message_id
        }
      end

      notifications.destroy_all
    end

    def broadcast_notification_removals
      return if @destroyed_notifications.blank?

      @destroyed_notifications.each do |destroyed|
        Turbo::StreamsChannel.broadcast_remove_to(
          [ destroyed[:user], :inbox_activity ],
          target: destroyed[:dom_id]
        )
      end

      # Every boost notification lands on the message's creator, so the grouped
      # refresh only needs to run once per recipient+message.
      @destroyed_notifications.uniq { |d| [ d[:user].id, d[:message_id] ] }.each do |destroyed|
        Notification::BoostGroup.broadcast_update_after_removal(
          user: destroyed[:user],
          message_id: destroyed[:message_id]
        )

        destroyed[:user].broadcast_activity_indicator
      end
    end

    # Matches turbo_frame_tag(message, :boosting) — the message dom key is its
    # client_message_id (Message#to_key).
    def boosts_frame_id
      "boosting_message_#{message.client_message_id}"
    end
end
