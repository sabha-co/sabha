module Room::Restorable
  extend ActiveSupport::Concern

  included do
    after_update_commit :broadcast_reactivation_if_restored
  end

  private
    def broadcast_reactivation_if_restored
      broadcast_reactivation if saved_change_to_attribute?(:active) && active?
    end

    def broadcast_reactivation
      return unless sidebar_room?

      memberships.visible.includes(:user).find_each do |membership|
        list_name = membership.sidebar_list_name
        Turbo::StreamsChannel.broadcast_append_to(
          membership.user, :rooms,
          target: list_name,
          partial: "users/sidebars/rooms/shared",
          locals: { list_name:, membership: membership, room: self },
          attributes: { maintain_scroll: true }
        )
      end
    end
end
