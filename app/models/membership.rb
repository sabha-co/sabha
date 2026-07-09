class Membership < ApplicationRecord
  include Cacheable, Connectable, Involvable, Starrable, Deactivatable, Notifiable

  belongs_to :room
  belongs_to :user

  # After the room association: Unreadable's unread_notifications goes through it.
  include Unreadable

  scope :with_ordered_room, -> { includes(:room).joins(:room).order("rooms.sortable_name") }
  scope :with_room_by_activity, -> { includes(:room).joins(:room).order("rooms.messages_count DESC") }
  scope :with_room_by_last_active_newest_first, -> { includes(:room).joins(:room).order("rooms.last_active_at DESC") }
  scope :with_room_chronologically, -> { includes(:room).joins(:room).order("rooms.created_at") }
  scope :with_room_by_sort_preference, ->(preference) {
    case preference
    when "alphabetical"
      with_ordered_room
    when "most_active"
      with_room_by_activity
    else
      with_room_by_last_active_newest_first
    end
  }
  scope :shared, -> { joins(:room).where(rooms: { type: %w[Rooms::Open Rooms::Closed Rooms::Forum] }) }
  scope :direct_rooms, -> { joins(:room).where(rooms: { type: "Rooms::Direct" }) }
  scope :without_direct_rooms, -> { joins(:room).where.not(rooms: { type: "Rooms::Direct" }) }
  scope :without_thread_rooms, -> { joins(:room).where.not(rooms: { type: %w[ Rooms::Thread Rooms::Post ] }) }
  scope :active_rooms, -> { joins(:room).where(rooms: { active: true }) }
  scope :with_messages, -> { joins(:room).where("rooms.messages_count > 0") }

  class LastVisibleMemberError < StandardError; end

  # User-initiated leave: clear involvement (cascades to starred via
  # Membership::Starrable#unstar_if_invisible). The row stays `active = true`.
  # Distinct from admin-driven User#deactivate / Room#deactivate, which flip
  # `active` instead and preserve involvement / starred / read-cursor state
  # for later reactivation.
  def leave!
    with_lock do
      room.ensure_visible_members_remain!(excluding: user_id)
      update!(involvement: :invisible)
    end
  end
end
