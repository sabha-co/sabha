module Membership::Cacheable
  extend ActiveSupport::Concern

  included do
    after_commit :invalidate_channel_member_count_cache
  end

  private
    def invalidate_channel_member_count_cache
      channel&.invalidate_member_count_cache

      # Also invalidate the previous channel's cache if channel_id changed
      if saved_change_to_channel_id? && channel_id_before_last_save
        Channel.find_by(id: channel_id_before_last_save)&.invalidate_member_count_cache
      end
    end
end
