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

  after_update_commit :broadcast_reactivation_if_restored
  after_update_commit :clear_unread_timestamps_if_deactivated
  after_update_commit :destroy_notifications_if_deactivated
  after_update_commit :destroy_stale_mention_notifications
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
  scope :created_by, ->(user) { where(creator_id: user.id) }
  scope :without_created_by, ->(user) { where.not(creator_id: user.id) }
  scope :between, ->(from, to) { where(created_at: from..to) }
  scope :since, ->(time) { where(created_at: time..) }
  scope :with_bookmark_status_for, ->(user) {
    joins(sanitize_sql_array([ <<~SQL.squish, user.id ])).select("messages.*, (bookmarks.id IS NOT NULL) AS is_bookmarked")
      LEFT JOIN bookmarks
        ON bookmarks.message_id = messages.id
        AND bookmarks.user_id = ?
    SQL
  }

  # Used by bookmarks inbox where all messages are known to be bookmarked
  attr_writer :bookmarked

  validate :ensure_can_message_recipient, on: :create
  validate :ensure_everyone_mention_allowed, on: :create

  def event?
    event.present?
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

      broadcast_mention_notifications(recipient_ids)
    end

    def create_thread_reply_notifications
      return unless room.thread? && room.parent_message

      CreateThreadReplyNotificationsJob.perform_later(message_id: id, thread_id: room.id, creator_id: creator_id)
    end

    def destroy_all_associated_records
      # Delete all boosts, bookmarks, and notifications to satisfy FK constraints.
      # Storage entries are intentionally preserved as an audit log (recordable is optional).
      Notification.where(message_id: id).delete_all
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

      # Find memberships where unread_at points to this deleted message
      room.memberships.where(unread_at: created_at).find_each do |membership|
        # Find the next unread message after this one, or mark as read
        next_unread = room.messages.active.ordered
                         .where("created_at > ?", created_at)
                         .first

        if next_unread
          membership.update!(unread_at: next_unread.created_at)
        else
          membership.read # This sets unread_at to nil and broadcasts read status
        end
      end
    end
end
