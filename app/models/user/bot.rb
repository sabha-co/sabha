require "digest"

module User::Bot
  extend ActiveSupport::Concern

  included do
    scope :active_bots, -> { active.where(role: :bot) }
    scope :without_bots, -> { where.not(role: :bot) }
    has_one :webhook, dependent: :destroy

    # The plaintext bearer key exists only in memory, only right after it is
    # minted (create or rotate). It is never persisted — we store its digest —
    # so this is the sole window in which the real key can be shown.
    attr_accessor :plaintext_bot_key

    # Editor-only: the settings editor requires a unique name, but the API
    # registration path (default context) stays lenient so a plugin can register
    # a nameless bot. A DB constraint would wrongly bind both paths.
    validates :name, presence: true, on: :editor
    validate :name_unique_among_bots, on: :editor
  end

  module ClassMethods
    def create_bot!(attributes)
      attributes = attributes.to_h.symbolize_keys
      webhook_secret = generate_webhook_secret
      webhook_url = attributes.delete(:webhook_url).presence || attributes.delete(:mentions_url).presence || attributes.delete(:everything_url).presence
      key = generate_bot_key

      transaction do
        User.create!(**attributes, bot_key_digest: bot_key_digest_for(key), bot_key_rotated_at: Time.current, webhook_secret: webhook_secret, role: :bot).tap do |user|
          user.create_webhook!(url: webhook_url) if webhook_url.present?
          user.plaintext_bot_key = key
        end
      end
    end

    # Hash exactly what the client presented (after one consistent strip) and
    # match it against the stored digest. The legacy fallback lets bots minted
    # before the digest cutover keep authenticating with their "<id>-<token>"
    # key until they rotate; new "sabha_bot_" keys have no hyphen, so they never
    # take that branch.
    def authenticate_bot(presented_key)
      return nil if presented_key.blank?

      key = presented_key.strip
      active_bots.find_by(bot_key_digest: bot_key_digest_for(key)) || authenticate_bot_by_legacy_token(key)
    end

    def bot_key_digest_for(key)
      Digest::SHA256.hexdigest(key.to_s.strip)
    end

    def generate_bot_key
      "sabha_bot_#{SecureRandom.hex(16)}"
    end

    def generate_bot_token
      SecureRandom.alphanumeric(12)
    end

    def generate_webhook_secret
      "whsec_#{SecureRandom.alphanumeric(40)}"
    end

    private
      def authenticate_bot_by_legacy_token(key)
        bot_id, bot_token = key.split("-", 2)
        return nil if bot_token.blank?
        active_bots.find_by(id: bot_id, bot_token: bot_token)
      end
  end

  def update_bot!(attributes)
    attributes = attributes.to_h.symbolize_keys
    has_webhook_param = attributes.key?(:webhook_url) || attributes.key?(:mentions_url) || attributes.key?(:everything_url)
    webhook_url = attributes.delete(:webhook_url).presence || attributes.delete(:mentions_url).presence || attributes.delete(:everything_url).presence

    transaction do
      update_webhook_url!(webhook_url) if has_webhook_param
      update!(attributes)
    end
  end

  # The real key, but only while it's freshly minted (plaintext_bot_key set) or
  # for a legacy bot whose derivable token is still on file. A rotated or new
  # bot loaded from the database returns nil here by design — the key is gone.
  def bot_key
    plaintext_bot_key || legacy_bot_key
  end

  def reset_bot_key
    key = self.class.generate_bot_key
    update!(bot_key_digest: self.class.bot_key_digest_for(key), bot_key_rotated_at: Time.current, bot_token: nil)
    self.plaintext_bot_key = key
    self
  end

  def webhook_url
    webhook&.url
  end

  def webhook_configured?
    webhook_url.present? && webhook_secret.present?
  end

  def room_memberships
    memberships.visible.without_direct_rooms.without_thread_rooms.where(rooms: { active: true })
  end

  def rooms_available_to_add
    Room.active.without_directs.without_threads.where.not(id: room_memberships.select(:room_id)).ordered
  end

  # Reconcile the bot's room memberships to exactly the given set — the editor's
  # room chips are the source of truth, so this both joins and leaves. Bot
  # memberships are pinned to "mentions"; the editor exposes no per-room involvement.
  def sync_rooms!(room_ids, actor:)
    desired = Room.active.without_directs.without_threads.where(id: room_ids).to_a
    current = room_memberships.map(&:room)

    (desired - current).each { |room| room.add_member!(self, actor: actor) }
    (current - desired).each { |room| room.remove_member!(self, actor: actor) }

    memberships.where(room: desired).where.not(involvement: :mentions).find_each do |membership|
      membership.update!(involvement: :mentions)
    end
  end

  def deliver_webhook_later(item, event, reply: false, base_url: "")
    webhook&.deliver_later(item, event, reply: reply, base_url: base_url)
  end

  private
    def name_unique_among_bots
      if User.active_bots.where(name: name).where.not(id: id).exists?
        errors.add(:name, "A bot already uses that name.")
      end
    end

    def legacy_bot_key
      "#{id}-#{bot_token}" if bot_token.present?
    end

    def update_webhook_url!(url)
      if url.present?
        webhook&.update!(url: url) || create_webhook!(url: url)
      else
        webhook&.destroy
      end
    end
end
