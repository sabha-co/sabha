module Room::Sortable
  extend ActiveSupport::Concern

  included do
    before_save :set_sortable_name
    after_save_commit :broadcast_updates, if: :saved_change_to_sortable_name?
  end

  private
    def set_sortable_name
      self.sortable_name = name.to_s.gsub(/[[:^ascii:]\p{So}]/, "").strip.downcase
    end

    def broadcast_updates
      Account.sole.broadcast_room_list({ roomId: id, sortableName: sortable_name })
    rescue ActiveRecord::RecordNotFound
      # No account yet (e.g., during setup or seed)
    end
end
