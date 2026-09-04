class Message < ApplicationRecord
  include Attachment, Broadcasts, Mentionee, Pagination, Pinnable, Searchable, Streakable, Threadable, Unreadable, Deactivatable

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
  after_create_commit :dispatch_notifications
  after_update_commit :broadcast_reactivation_if_restored

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
      .includes(room: { parent_message: :room })
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

  # Active messages a user can reach: those in an active room they belong to, plus
  # those in a nested sub-room (forum post / chat thread) whose PARENT they belong
  # to — sub-room access derives from the parent, not a per-sub-room membership. So
  # a passive parent member reaches a sub-room they never joined, and a silenced-
  # but-active row a user keeps after leaving the parent grants no reach (its room
  # fails the parent check). Backs search, unreads, the inbox feed, and User#reachable_message(s).
  scope :reachable_by, ->(user) {
    mine = Membership.active.where(user_id: user.id).select(:room_id)
    normal_rooms = Room.active.where(id: mine).where.not(type: Room::SUB_ROOM_TYPES)
    sub_rooms    = Room.active.where(type: Room::SUB_ROOM_TYPES, parent_room_id: mine)
    active.where(room_id: normal_rooms.or(sub_rooms).select(:id))
  }

  # Composite cursor for stable pagination across timestamp ties.
  # Pairs with an ORDER BY (created_at DESC, id DESC) — emit cursor from the
  # last row of a page, pass it back to skip past that exact (time, id) point.
  scope :before_cursor, ->(time, id) {
    table = arel_table
    where(table[:created_at].lt(time))
      .or(where(table[:created_at].eq(time)).where(table[:id].lt(id)))
  }
  # Mirror of before_cursor: everything strictly after a (time, id) point.
  # Powers derived unread — messages after a membership's read cursor.
  scope :after_cursor, ->(time, id) {
    table = arel_table
    where(table[:created_at].gt(time))
      .or(where(table[:created_at].eq(time)).where(table[:id].gt(id)))
  }
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

  # The forum post (Rooms::Post) this message belongs to, or nil for non-post
  # messages. A post's messages ARE its content — the opening body and the
  # replies — so the post is simply the message's room. Permalinks resolve post
  # messages to the forum gallery deep-link (?post=<slug>) through this.
  def forum_post
    room if room.post?
  end

  def bookmarked_by?(user)
    # Scope path: with_bookmark_status_for LEFT JOIN sets is_bookmarked
    # Use ActiveRecord::Type::Boolean to handle SQLite's 0/1/"0"/"1" values
    return ActiveRecord::Type::Boolean.new.cast(is_bookmarked) if has_attribute?(:is_bookmarked)
    # Manual path: bookmarks inbox sets @bookmarked = true
    return @bookmarked if instance_variable_defined?(:@bookmarked)
    # Fallback: single message query (e.g., thread parent)
    bookmarks.exists?(user_id: user&.id)
  end

  def plain_text_body
    body.to_plain_text.presence || attachment&.filename&.to_s || ""
  end

  # Aggregates this message's boosts into emoji-content groups, returning
  # `[groups, total, truncated]`. Groups are sorted count DESC, then earliest
  # reaction ASC. Boosters within a group are sorted oldest-first.
  #
  # Caps are applied in SQL (GROUP BY + per-group LIMIT) so a heavily-reacted
  # message never materializes more than ~limit × boosters_limit rows in Ruby.
  # Issues O(distinct_emoji) queries by design — bounded by `limit + 1` —
  # SQLite portability rules out a single `array_agg`. boost_groups is the
  # in-memory sibling used by the web render; keep their ranking rules in step.
  def boost_summary(limit: 50, boosters_limit: Boost::BOOSTERS_LISTED)
    ranked = boosts.group(:content)
                   .reorder(Arel.sql("COUNT(*) DESC, MIN(created_at) ASC"))
                   .limit(limit + 1)
                   .pluck(:content, Arel.sql("COUNT(*)"), Arel.sql("MIN(created_at)"))

    truncated = ranked.size > limit
    visible = ranked.first(limit)

    groups = visible.map do |content, count, _earliest|
      sample = boosts.where(content: content)
                     .reorder(:created_at)
                     .limit(boosters_limit)
                     .includes(:booster)
      Boost::Group.new(
        content: content,
        count: count,
        boosters: sample.map(&:booster),
        truncated: count > boosters_limit
      )
    end

    [ groups, boosts.count, truncated ]
  end

  # The in-memory sibling of boost_summary: one chip per distinct reaction,
  # boosters oldest-first within a group, groups ordered by count DESC then
  # earliest reaction ASC — the same ranking rule, kept in step. This variant
  # groups in Ruby off the loaded association so rendering the message list stays
  # free of the per-message queries boost_summary issues, and is intentionally
  # uncapped: the web preloads the whole set and a message's distinct-emoji count
  # is naturally small. boost_summary is the SQL-capped variant for the API's
  # unbounded callers.
  def boost_groups
    # Memoized: a reaction toggle re-renders this container to two streams (room
    # + inbox) off the same message instance, so the grouping — and its
    # boosts+boosters query on the standalone path — runs once, not per render.
    @boost_groups ||= begin
      # The message list preloads boosts + boosters; standalone renders (the boost
      # broadcast and the create/destroy responses) don't, so pull boosters in one
      # query there rather than one per reaction. Reuse the preloaded association
      # when it's already loaded so the list stays a no-extra-query render.
      source = boosts.loaded? ? boosts : boosts.includes(:booster)

      # The association is ordered by created_at, so each group is already
      # oldest-first and group.first is the earliest reaction of that emoji.
      source.group_by(&:content).values
            .sort_by { |group| [ -group.size, group.first.created_at ] }
            .map do |group|
              Boost::Group.new(
                content: group.first.content,
                count: group.size,
                boosters: group.map(&:booster),
                truncated: false
              )
            end
    end
  end

  # Drops the memoized grouping so the next #boost_groups recomputes. A reaction
  # commit re-renders the chip container off the boost's message instance twice
  # (room + inbox stream); resetting once per toggle keeps that instance fresh
  # across sequential toggles while the two renders still share one query.
  def reset_boost_groups
    @boost_groups = nil
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

  # Single dispatch entry point invoked by Notification::DispatchJob. Iterates
  # the activity types applicable to this message in this room and runs each
  # channel branch. The in-app row branch is currently a no-op pass-through —
  # the legacy `create_mention_notifications` and
  # `create_thread_reply_notifications` callbacks still write rows.
  #
  # Boost is the lone special case: passes `only: :boost, actor: booster`.
  def notify_recipients(only: nil, actor: nil)
    return if event?

    types = only ? Array(only).map(&:to_sym) : room.applicable_activity_types(self)
    push_subscriptions = []

    # Two phases. Everything that can raise — in-app rows, email bundles, and
    # working out who to push — runs first; posting runs last. A push can't be
    # recalled once posted, so a raise afterwards (the next activity type's
    # email work, say) would re-send it when the job retries.
    types.each do |activity_type|
      deliver_in_app_row_for(activity_type, actor: actor)              if Notification::Routing::IN_APP_ROW_TYPES.include?(activity_type)
      push_subscriptions.concat push_subscriptions_for(activity_type)  if Notification::Routing::PUSH_TYPES.include?(activity_type)
      enqueue_missed_email_candidates_for(activity_type)               if Notification::Routing::EMAIL_TYPES.include?(activity_type)
    end

    deliver_pushes_to push_subscriptions
  end

  # Block ids touching this message's creator — memoized so per-recipient
  # predicates can do a Set lookup instead of two `exists?` queries each.
  # An @everyone push in a 500-member room would otherwise issue 1000 block
  # queries through `User#can_ping?`; with this cache it's two, total.
  def blocked_user_ids_with_creator
    @blocked_user_ids_with_creator ||= begin
      return [].to_set unless creator_id

      (Block.where(blocker_id: creator_id).pluck(:blocked_id) +
       Block.where(blocked_id: creator_id).pluck(:blocker_id)).to_set
    end
  end

  # Returns the candidate user-id set for a push activity type. The membership
  # scopes pre-filter for speed (involvement, creator exclusion), anyone
  # currently watching the room is dropped, then
  # Membership::Notifiable#receives_push_for? applies the full gate so block
  # checks, user health, message/room state, and the push_enabled setting all
  # participate — same predicates run at dispatch time and at delivery time,
  # per arch § 4–5.
  def push_recipient_user_ids_for(activity_type)
    activity_type = activity_type.to_sym
    return [] unless Notification::Routing::PUSH_TYPES.include?(activity_type)

    push_candidate_memberships_for(activity_type)
      .reject { |membership| watching?(membership) }
      .select { |membership| membership.receives_push_for?(self, activity_type) }
      .map(&:user_id)
  end

  # Walks the candidate recipient set for `activity_type`, runs
  # `Membership::Notifiable#receives_missed_email_for?` per membership, and
  # appends a BundleItem to each eligible user's active bundle.
  def enqueue_missed_email_candidates_for(activity_type)
    activity_type = activity_type.to_sym
    return unless Notification::Routing::EMAIL_TYPES.include?(activity_type)

    candidate_user_ids = email_candidate_user_ids_for(activity_type)
    return if candidate_user_ids.empty?

    # Preload notification_settings: receives_missed_email_for? reads it for the
    # account/user gate, so without this include each predicate call is N+1.
    eligible_memberships = room.memberships
      .where(user_id: candidate_user_ids)
      .includes(user: :notification_settings)
      .select { |membership| membership.receives_missed_email_for?(self, activity_type) }
    return if eligible_memberships.empty?

    bundles_by_user_id = bundles_for(eligible_memberships.map(&:user))

    kind = activity_type.to_s
    now  = Time.current
    item_attrs = eligible_memberships.map do |membership|
      {
        bundle_id:  bundles_by_user_id.fetch(membership.user_id).id,
        message_id: id,
        actor_id:   creator_id,
        kind:       kind,
        created_at: now,
        updated_at: now
      }
    end

    Notification::BundleItem.insert_all(item_attrs, unique_by: %i[bundle_id message_id kind])

    # Schedule delivery once per freshly-opened bundle. Bundles already open from
    # a prior message already have a delivery scheduled.
    bundles_by_user_id.each_value do |bundle|
      bundle.schedule_delivery if bundle.previously_new_record?
    end
  end

  private
    # Who has this room open right now, straight from anycable-go, which holds
    # their sockets. Memoized because notify_recipients runs up to three activity
    # types and they must agree with each other — and because it's an HTTP call.
    # nil means the broker couldn't answer, which is not the same as nobody being
    # here, so `defined?` rather than `||=`.
    def watching_user_ids
      return @watching_user_ids if defined?(@watching_user_ids)

      @watching_user_ids = Room::PresenceSet.for(room)
    end

    def watching?(membership)
      if watching_user_ids
        watching_user_ids.include?(membership.user_id)
      else
        # No live signal, so fall back to the column presence replaced. Coarser
        # and staler, but it only fires when anycable-go is unreachable — which
        # is also when these members are receiving no live messages anyway.
        membership.connected?
      end
    end

    def push_subscriptions_for(activity_type)
      user_ids = push_recipient_user_ids_for(activity_type)
      return [] if user_ids.empty?

      Push::Subscription.where(user_id: user_ids).to_a
    end

    # Phase 2. Deliberately dumb: everything that can fail has already run. The
    # payload is built before the first post, so a raise here still means
    # nothing went out and the job can retry cleanly.
    def deliver_pushes_to(subscriptions)
      return if subscriptions.empty?

      payload = Room::MessagePusher.payload_for(room: room, message: self)
      Rails.configuration.x.web_push_pool.queue(payload, subscriptions)
    end

    def push_candidate_memberships_for(activity_type)
      eager_load = { user: :notification_settings }

      case activity_type
      when :everyone_room_message
        room.memberships.visible
            .where.not(user_id: creator_id)
            .involved_in_everything
            .includes(eager_load)
      when :thread_reply
        # Sub-room followers (chat threads and forum posts) sit at involvement
        # :everything via Room::Followable#follow!. receives_push_for?(:thread_reply)
        # qualifies anyone !involved_in_invisible?, so the `.visible` scope already
        # does all the filtering needed here — and it still covers any legacy
        # :mentions rows from before the sub-room levels were unified.
        room.memberships.visible
            .where.not(user_id: creator_id)
            .includes(eager_load)
      when :direct_message
        room.memberships.visible
            .where.not(user_id: creator_id)
            .includes(eager_load)
      when :mention
        candidate_user_ids = mentions_everyone? ? room.user_ids - [ creator_id ] : mentionee_ids - [ creator_id ]
        room.memberships.visible
            .where(user_id: candidate_user_ids)
            .involved_in_mentions
            .includes(eager_load)
      else
        Membership.none
      end
    end

    # Single batched lookup of each user's active bundle, opening new ones for
    # users without one. Avoids the per-recipient SELECT (+ INSERT on miss) that
    # User#active_notification_bundle would otherwise issue inside the dispatch
    # loop on a hot @everyone path.
    def bundles_for(users)
      existing = Notification::Bundle.active.where(user_id: users.map(&:id)).index_by(&:user_id)
      users.each_with_object(existing) do |user, by_id|
        by_id[user.id] ||= user.open_notification_bundle!
      end
    end

    def email_candidate_user_ids_for(activity_type)
      case activity_type
      when :mention
        mentions_everyone? ? room.user_ids - [ creator_id ] : mentionee_ids - [ creator_id ]
      when :direct_message
        room.user_ids - [ creator_id ]
      else
        []
      end
    end

    def deliver_in_app_row_for(activity_type, actor: nil)
      case activity_type
      when :mention, :thread_reply
        # Legacy `create_mention_notifications` and
        # `create_thread_reply_notifications` callbacks still own row creation;
        # the dispatch job no-ops here. The partial unique index
        # `index_notifications_on_message_user_type` is the safety net if both
        # paths ever fire.
      when :boost
        create_boost_notification_row(actor: actor)
      end
    end

    def create_boost_notification_row(actor:)
      return unless actor
      boost = boosts.find_by(booster_id: actor.id)
      return unless boost

      # Idempotent on boost_id: rapid re-reactions can enqueue several dispatch
      # jobs that all resolve to the same surviving boost, and a boost notifies
      # its single recipient (the creator) exactly once. create_or_find_by leans
      # on the unique index to settle the race, so a duplicate job finds the
      # existing row instead of adding a second.
      notification = Notification.create_or_find_by!(boost_id: boost.id) do |n|
        n.user_id = creator_id
        n.message_id = id
        n.actor_id = actor.id
        n.activity_type = "boost"
      end
      return unless notification.previously_new_record?

      Turbo::StreamsChannel.broadcast_append_to(
        [ notification.user, :inbox_activity ],
        target: "inbox",
        partial: "notifications/notification",
        locals: { notification: notification }
      )

      notification.user.broadcast_activity_indicator
    end

  private
    # Bots and API consumers don't generate client-side IDs for Turbo dedup
    def set_default_client_message_id
      self.client_message_id ||= SecureRandom.uuid
    end

    def broadcast_reactivation_if_restored
      broadcast_reactivation if saved_change_to_attribute?(:active) && active?
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

    def dispatch_notifications
      return if event?

      Notification::DispatchJob.perform_later(self)
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
      Notification::BundleItem.where(message_id: id).delete_all
    end
end
