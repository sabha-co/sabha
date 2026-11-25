class Membership < ApplicationRecord
  # Dropped in favor of the read cursor (last_read_at, last_read_message_id,
  # marked_unread). Ignoring it keeps inserts from naming the column on a
  # database the drop migration hasn't reached yet.
  self.ignored_columns += %w[ unread_at ]

  include Cacheable, Connectable, Involvable, Starrable, Deactivatable, Notifiable

  belongs_to :channel
  belongs_to :user

  # After the channel association: Unreadable's unread_notifications goes through it.
  include Unreadable

  scope :with_ordered_channel, -> { includes(:channel).joins(:channel).order("channels.sortable_name") }
  scope :with_channel_by_activity, -> { includes(:channel).joins(:channel).order("channels.messages_count DESC") }
  scope :with_channel_by_last_active_newest_first, -> { includes(:channel).joins(:channel).order("channels.last_active_at DESC") }
  scope :with_channel_chronologically, -> { includes(:channel).joins(:channel).order("channels.created_at") }
  scope :with_channel_by_sort_preference, ->(preference) {
    case preference
    when "alphabetical"
      with_ordered_channel
    when "most_active"
      with_channel_by_activity
    else
      with_channel_by_last_active_newest_first
    end
  }
  scope :shared, -> { joins(:channel).where(channels: { type: %w[Channels::Open Channels::Closed Channels::Forum] }) }
  scope :direct_channels, -> { joins(:channel).where(channels: { type: "Channels::Direct" }) }
  scope :without_direct_channels, -> { joins(:channel).where.not(channels: { type: "Channels::Direct" }) }
  scope :without_thread_channels, -> { joins(:channel).where.not(channels: { type: %w[ Channels::Thread Channels::Post ] }) }
  scope :active_channels, -> { joins(:channel).where(channels: { active: true }) }
  scope :with_messages, -> { joins(:channel).where("channels.messages_count > 0") }

  class LastVisibleMemberError < StandardError; end

  # User-initiated leave: clear involvement (cascades to starred via
  # Membership::Starrable#unstar_if_invisible). The row stays `active = true`.
  # Distinct from admin-driven User#deactivate / Channel#deactivate, which flip
  # `active` instead and preserve involvement / starred / read-cursor state
  # for later reactivation.
  def leave!
    with_lock do
      channel.ensure_visible_members_remain!(excluding: user_id)
      update!(involvement: :invisible)
    end
  end
end
