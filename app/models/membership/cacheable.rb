module Membership::Cacheable
  extend ActiveSupport::Concern

  included do
    after_commit :invalidate_room_member_count_cache
  end

  private
    def invalidate_room_member_count_cache
      room&.invalidate_member_count_cache

      # Also invalidate the previous room's cache if room_id changed
      if saved_change_to_room_id? && room_id_before_last_save
        Room.find_by(id: room_id_before_last_save)&.invalidate_member_count_cache
      end
    end
end
