module Membership::Involvable
  extend ActiveSupport::Concern

  included do
    enum :involvement, %w[ invisible nothing mentions everything ].index_by(&:itself), prefix: :involved_in

    scope :visible,          -> { where.not(involvement: :invisible) }
    scope :notifications_on, -> { where(involvement: :everything) }

    after_update :broadcast_involvement, if: :saved_change_to_involvement?
  end

  def receives_mentions?
    involved_in_mentions? || involved_in_everything?
  end

  # Per-room involvement after applying the global mode override. Predicates
  # ask this only — they don't read mode and involvement independently.
  # Per-room :everything wins (opt-in beats global mute); otherwise global
  # :nothing applies; else fall back to per-room involvement.
  def effective_involvement
    return :everything if involved_in_everything?
    return :nothing if user.try(:notification_settings)&.mode == "nothing"
    involvement.to_sym
  end

  def ensure_receives_mentions!
    update(involvement: :mentions) if involved_in_invisible?
  end

  private
    def broadcast_involvement
      UserInvolvementsChannel.broadcast_to(user, { roomId: room_id, involvement: involvement })
    end
end
