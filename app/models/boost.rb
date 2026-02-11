class Boost < ApplicationRecord
  include Deactivatable

  belongs_to :message, touch: true
  belongs_to :booster, class_name: "User", default: -> { Current.user }

  validates :content, uniqueness: { scope: [ :message_id, :booster_id ], conditions: -> { active } }

  scope :ordered, -> { order(:created_at) }

  after_create_commit :broadcast_create
  after_update_commit :broadcast_reactivation, if: -> { saved_change_to_attribute?(:active) && active? }
  after_update_commit :broadcast_deactivation, if: -> { saved_change_to_attribute?(:active) && !active? }

  private
    def broadcast_create
      broadcast_append_to message.room, :messages, target: boosts_target, partial: "messages/boosts/boost", locals: { boost: self }
      broadcast_append_to :inbox, target: boosts_target, partial: "messages/boosts/boost", locals: { boost: self }
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
