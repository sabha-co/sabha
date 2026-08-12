module Membership::Starrable
  extend ActiveSupport::Concern

  included do
    scope :starred,   -> { where(starred: true) }
    scope :unstarred, -> { where(starred: false) }

    validate :starred_only_for_shared_visible_rooms, if: :starred?
    before_validation :unstar_if_invisible

    after_update_commit :broadcast_star_change, if: :saved_change_to_starred?
  end

  def sidebar_list_name
    if starred?
      :starred_rooms
    elsif room.forum?
      :forum_rooms
    else
      :shared_rooms
    end
  end

  private
    def starred_only_for_shared_visible_rooms
      if room.direct? || room.thread?
        errors.add(:starred, "is not allowed for direct or thread rooms")
      end
    end

    # Cascade for Membership#leave! — leaving a room sets involvement to
    # :invisible, which implies the room can't show up in the starred sidebar
    # list. This callback keeps that invariant on every involvement write.
    def unstar_if_invisible
      self.starred = false if involved_in_invisible? && starred?
    end

    def broadcast_star_change
      return if involved_in_invisible? || room.direct? || room.thread?

      old_list = starred_before_last_save ? :starred_rooms : :shared_rooms

      Turbo::StreamsChannel.broadcast_remove_to(
        user, :rooms,
        target: [ room, "#{old_list}_list_node" ]
      )

      Turbo::StreamsChannel.broadcast_append_to(
        user, :rooms,
        target: sidebar_list_name,
        partial: "users/sidebars/rooms/shared",
        locals: { list_name: sidebar_list_name, membership: self },
        attributes: { maintain_scroll: true }
      )
    end
end
