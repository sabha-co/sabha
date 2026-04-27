class Message < ApplicationRecord
  include Attachment, Broadcasts, Mentionee, Pagination, Searchable, Deactivatable

  belongs_to :room, counter_cache: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }

  has_many :boosts, -> { order(:created_at) }, class_name: "Boost"
  has_many :bookmarks, class_name: "Bookmark"

  has_many :threads, class_name: "Rooms::Thread", foreign_key: :parent_message_id, dependent: :destroy

  # Clean up associated records before destroying
  before_destroy :destroy_all_associated_records

  has_rich_text :body

  before_create :set_default_client_message_id
  before_create :touch_room_activity
  after_create_commit :deliver_to_room
  after_create_commit :involve_creator_in_thread
  after_create_commit :update_thread_reply_count
  after_create_commit :update_parent_message_threads
  after_create_commit :update_creator_streak
  after_create_commit :create_mention_notifications
  after_create_commit :create_thread_reply_notifications
  after_create_commit :increment_unread_notifications_counters

  after_update_commit :broadcast_reactivation_if_restored
  after_update_commit :clear_unread_timestamps_if_deactivated
  after_update_commit :destroy_notifications_if_deactivated
  after_update_commit :destroy_stale_mention_notifications
  after_update_commit :restore_unread_notifications_counters_if_reactivated
  after_update_commit :broadcast_parent_message_to_threads

  scope :ordered, -> { order(:created_at) }
  scope :without_events, -> { where(event: nil) }
  scope :user_authored, -> { where(event: nil, welcome: false) }
  scope :with_creator, -> { includes(creator: [ :badge, { avatar_attachment: { blob: :variant_records } } ]) }
  # Lightweight thread loading - fetches threads but NOT their messages
  # The partial uses Rooms::Thread#participant_creators for efficient participant fetching
  scope :with_thread_summary, -> { includes(:threads) }
  scope :for_display, -> {
    with_rich_text_body_and_embeds
      .with_creator
      .includes(attachment_attachment: { blob: :variant_records })
      .includes(boosts: { booster: { avatar_attachment: { blob: :variant_records } } })
      .with_thread_summary
  }
  scope :created_by, ->(users) { where(creator_id: Array.wrap(users).map { |u| u.is_a?(User) ? u.id : u }) }
  scope :without_created_by, ->(user) { where.not(creator_id: user.id) }
  scope :between, ->(from, to) { where(created_at: from..to) }
  scope :since, ->(time) { where(created_at: time..) }
  scope :created_before, ->(time) { where(created_at: ..time) }
  scope :in_rooms, ->(ids) { where(room_id: ids) }
  scope :with_bookmark_status_for, ->(user) {
    joins(sanitize_sql_array([ <<~SQL.squish, user.id ])).select("messages.*, (bookmarks.id IS NOT NULL) AS is_bookmarked")
      LEFT JOIN bookmarks
        ON bookmarks.message_id = messages.id
        AND bookmarks.user_id = ?
    SQL
  }

  # Used by bookmarks inbox where all messages are known to be bookmarked
  attr_writer :bookmarked, :thread_participants

  validate :ensure_can_message_recipient, on: :create
  validate :ensure_everyone_mention_allowed, on: :create

  def event?
    event.present?
  end

  # Callers should preload :threads before invoking this to avoid per-message
  # association loads. The shared message scopes that render message lists
  # already do this via with_thread_summary / for_display.
  def self.with_thread_participants(messages, limit: 5)
    messages = messages.to_a
    return messages if messages.empty?

    thread_participants = Rooms::Thread.preload_participant_creators(messages.flat_map(&:threads).uniq, limit:)
    messages.each { |message| message.thread_participants = thread_participants }
    messages
  end

  def repliable?
    !event?
  end

  def bookmarked_by_current_user?
    # Scope path: with_bookmark_status_for LEFT JOIN sets is_bookmarked
    # Use ActiveRecord::Type::Boolean to handle SQLite's 0/1/"0"/"1" values
    return ActiveRecord::Type::Boolean.new.cast(is_bookmarked) if has_attribute?(:is_bookmarked)
    # Manual path: bookmarks inbox sets @bookmarked = true
    return @bookmarked if instance_variable_defined?(:@bookmarked)
    # Fallback: single message query (e.g., thread parent)
    bookmarks.exists?(user_id: Current.user&.id)
  end

  def plain_text_body
    body.to_plain_text.presence || attachment&.filename&.to_s || ""
  end

  def thread_participants_for(thread)
    @thread_participants&.fetch(thread.id, nil)
  end

  def thread_fingerprint
    threads.loaded? ? threads.map { |t| [ t.id, t.messages_count, t.active ] }
                    : threads.pluck(:id, :messages_count, :active)
  end

  def to_key
    [ client_message_id ]
  end

  def edited?
    updated_at > created_at + 30.seconds
  end

  def content_type
    case
    when attachment?    then "attachment"
    when sound.present? then "sound"
    else                     "text"
    end.inquiry
  end

  def sound
    plain_text_body.match(/\A\/play (?<name>\w+)\z/) do |match|
      Sound.find_by_name match[:name]
    end
  end

  def storage_tracked_record = self

  private
    # Bots and API consumers don't generate client-side IDs for Turbo dedup
    def set_default_client_message_id
      self.client_message_id ||= Random.uuid
    end

    def deliver_to_room
      room.receive(self)
    end

    def update_creator_streak
      return if room.direct? || room.parent_room&.direct? || welcome?
      UpdateStreakJob.perform_later(user_id: creator_id, excluding_message_id: id)
    end

    def broadcast_reactivation_if_restored
      broadcast_reactivation if saved_change_to_attribute?(:active) && active?
    end

    def involve_creator_in_thread
      # When someone posts in a thread, ensure they have visible membership
      room.involve_user(creator, unread: false) if room.thread?
    end

    def update_thread_reply_count
      # When a message is created in a thread, update the reply count separator
      if room.thread?
        broadcast_update_to(
          room,
          :messages,
          target: "#{ActionView::RecordIdentifier.dom_id(room, :replies_separator)}_count",
          html: ActionController::Base.helpers.pluralize(room.messages_count, "reply", "replies")
        )
      end
    end

    def update_parent_message_threads
      # When a message is created in a thread, update the parent message's threads display
      if room.thread? && room.parent_message
        broadcast_replace_to(
          room.parent_message.room,
          :messages,
          target: ActionView::RecordIdentifier.dom_id(room.parent_message, :threads),
          partial: "messages/threads",
          locals: { message: room.parent_message }
        )
      end
    end

    def broadcast_parent_message_to_threads
      # When a parent message is deleted/updated, broadcast to all threads
      if saved_change_to_attribute?(:active) && threads.any?
        threads.each do |thread|
          broadcast_replace_to(
            thread,
            :messages,
            target: ActionView::RecordIdentifier.dom_id(self),
            partial: "messages/parent_message",
            locals: { message: self, thread: thread }
          )
        end
      end
    end

    def touch_room_activity
      room.touch(:last_active_at)
    end

    def ensure_can_message_recipient
      errors.add(:base, "Messaging this user isn't allowed") if creator.blocked_in?(room)
    end

    def ensure_everyone_mention_allowed
      return unless body.body

      has_everyone_mention = body.body.attachables.any? { |a| a.is_a?(Everyone) }
      return unless has_everyone_mention

      if !room.is_a?(Rooms::Open)
        errors.add(:base, "@everyone is only allowed in open rooms")
      elsif !creator&.administrator?
        errors.add(:base, "Only admins can mention @everyone")
      end
    end

    def create_mention_notifications
      return if event?
      return if room.direct? || room.parent_room&.direct?

      recipient_ids = if mentions_everyone?
        room.user_ids - [ creator_id ]
      else
        mentionee_ids - [ creator_id ]
      end

      return if recipient_ids.empty?

      now = Time.current
      Notification.insert_all(
        recipient_ids.map { |uid|
          { user_id: uid, message_id: id, actor_id: creator_id, activity_type: "mention", created_at: now, updated_at: now }
        },
        unique_by: "index_notifications_on_message_user_type"
      )

      broadcast_mention_notifications
    end

    def create_thread_reply_notifications
      return unless room.thread? && room.parent_message

      CreateThreadReplyNotificationsJob.perform_later(message_id: id, thread_id: room.id, creator_id: creator_id)
    end

    # Bumps unread_notifications_count for memberships affected by this message.
    # Mirrors the with_has_unread_notifications semantics: DM rooms count every
    # unread message (including the sender's, matching the old scope which made
    # no creator distinction in DMs); other rooms only count mentions and
    # @everyone. Connected users (unread_at IS NULL) are skipped — they see
    # the message live, and senders almost always fall in this bucket.
    def increment_unread_notifications_counters
      return if event?

      recipient_ids = if room.direct?
        room.user_ids
      elsif mentions_everyone?
        room.user_ids - [ creator_id ]
      else
        mentionee_ids - [ creator_id ]
      end

      return if recipient_ids.empty?

      Membership.where(room_id: room_id, user_id: recipient_ids)
                .where("unread_at IS NOT NULL AND unread_at <= ?", created_at)
                .update_all("unread_notifications_count = unread_notifications_count + 1")
    end

    # When a soft-deleted message is reactivated (a console/admin path),
    # restore the counter bumps that clear_unread_timestamps_if_deactivated
    # took away. Only DM and @everyone messages are restored — named mentions
    # need their Notification rows back to count under either the old scope
    # or the new column, and we don't recreate those on reactivation.
    def restore_unread_notifications_counters_if_reactivated
      return unless saved_change_to_attribute?(:active) && active?
      return if event?
      return unless room.direct? || mentions_everyone?

      recipient_ids = room.direct? ? room.user_ids : room.user_ids - [ creator_id ]
      return if recipient_ids.empty?

      Membership.where(room_id: room_id, user_id: recipient_ids)
                .where("unread_at IS NOT NULL AND unread_at <= ?", created_at)
                .update_all("unread_notifications_count = unread_notifications_count + 1")
    end

    def destroy_all_associated_records
      # Delete all boosts, bookmarks, and notifications to satisfy FK constraints.
      # Storage entries are intentionally preserved as an audit log (recordable is optional).
      # delete_all_and_broadcast keeps memberships.unread_notifications_count honest
      # for non-DM rooms; DM and anchor cases are handled by rebalance_unread_counters.
      Notification.delete_all_and_broadcast(Notification.where(message_id: id))
      rebalance_unread_counters
      Boost.where(message_id: id).delete_all
      Bookmark.where(message_id: id).delete_all
    end

    def destroy_notifications_if_deactivated
      return unless saved_change_to_attribute?(:active) && !active?

      Notification.delete_all_and_broadcast(Notification.where(message_id: id))
    end

    def destroy_stale_mention_notifications
      return if room.direct?
      return unless active? # already handled by destroy_notifications_if_deactivated
      return unless rich_text_body.saved_changes?

      current_recipient_ids = if mentions_everyone_in_body?
        room.user_ids - [ creator_id ]
      else
        mentioned_users.map(&:id) - [ creator_id ]
      end

      Notification.delete_all_and_broadcast(
        Notification.where(message_id: id, activity_type: "mention")
                    .where.not(user_id: current_recipient_ids)
      )
    end

    def clear_unread_timestamps_if_deactivated
      return unless saved_change_to_attribute?(:active) && !active?
      rebalance_unread_counters
    end

    # Keeps memberships.unread_notifications_count and unread_at consistent
    # when this message disappears from the room (soft- or hard-deleted).
    #
    # Two effects per call:
    #   1. DMs only: every membership whose unread window contained this
    #      message loses one from its count (using < to leave the anchor
    #      membership for the second pass below).
    #   2. Any membership anchored exactly at this message's timestamp gets
    #      its anchor advanced to the next active message (or marked read),
    #      with its counter recomputed from the new anchor.
    def rebalance_unread_counters
      if room.direct?
        Membership.where(room_id: room_id)
                  .where("unread_at IS NOT NULL AND unread_at < ?", created_at)
                  .update_all("unread_notifications_count = MAX(unread_notifications_count - 1, 0)")
      end

      room.memberships.where(unread_at: created_at).find_each do |membership|
        next_unread = room.messages.active.ordered
                         .where("created_at > ?", created_at)
                         .first

        if next_unread
          membership.update!(
            unread_at: next_unread.created_at,
            unread_notifications_count: membership.count_unread_notifications_from(next_unread.created_at)
          )
        else
          membership.read # This sets unread_at to nil and broadcasts read status
        end
      end
    end
end
