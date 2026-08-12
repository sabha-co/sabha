class Account < ApplicationRecord
  include Joinable, Account::Storage

  # The custom-CSS feature is retired but its column still exists. Ignore it so
  # a later migration can drop the column without breaking rolling deploys.
  self.ignored_columns += %w[custom_styles]

  VALID_AUTH_METHODS = %w[password otp sso].freeze
  ALLOWED_LOGO_CONTENT_TYPES = %w[ image/jpeg image/png image/gif image/webp ].freeze

  # The workspace accent drives every interactive tint via [data-accent] on the
  # html element (see app/assets/stylesheets/application/colors.css).
  ACCENTS = %w[indigo ink forest rust plum].freeze

  InvalidLogoType = Class.new(StandardError)

  has_one_attached :logo do |attachable|
    attachable.variant :large, resize_to_limit: [ 512, 512 ], format: :png
    attachable.variant :small, resize_to_limit: [ 192, 192 ], format: :png
  end

  has_json :settings, restrict_room_creation_to_administrators: false, restrict_direct_messages_to_administrators: false, allow_users_to_create_invite_links: true, accent: "indigo"

  validate :accent_must_be_shipped

  after_save :invalidate_personal_invite_links, if: :invite_links_disabled?
  after_commit :sync_name_to_workspace, if: :saved_change_to_name?

  # Auth config is ENV-driven and shared across all accounts on a deploy.
  class << self
    def auth_method
      ENV["AUTH_METHOD"].presence_in(VALID_AUTH_METHODS) || "password"
    end

    def password_auth?
      auth_method == "password"
    end

    def otp_auth?
      auth_method == "otp"
    end

    def sso_auth?
      !Sabha.saas? && auth_method == "sso"
    end

    def sso_configured?
      (sso_auth? || FirstRun.should_auto_bootstrap?) &&
        sso_provider_url.present? && sso_secret.present?
    end

    def sso_provider_url
      ENV["SSO_PROVIDER_URL"]
    end

    def sso_secret
      ENV["SSO_SECRET"]
    end
  end

  def attach_logo(attachable)
    content_type = attachable.try(:content_type) || attachable[:content_type]
    raise InvalidLogoType unless content_type.in?(ALLOWED_LOGO_CONTENT_TYPES)

    logo.attach(attachable)
    touch
    sync_logo_to_workspace
  end

  def purge_logo
    logo.purge
    touch
    sync_logo_to_workspace
  end

  # nil when the logo can't be resized, so callers fall back to the stock icon. See
  # User::Avatar#avatar_variant for why a declared image type is no guarantee.
  def logo_variant(size)
    return unless logo.attached? && logo.variable?

    logo.variant(size).processed
  rescue Vips::Error => error
    Rails.logger.warn "Could not resize logo for account #{id}: #{error.message}"
    nil
  end

  # The account-wide room-list stream: one publish per room event (touched by
  # a message or post, renamed) that every member's open sidebar consumes. It
  # is a signed pub/sub stream rather than a channel — the sidebar subscribes
  # with the signed name and anycable-go verifies the signature itself, no
  # per-subscriber Rails round-trip. The name is built on the account's
  # GlobalID, which carries the tenant in SaaS, so streams never cross
  # workspaces.
  def broadcast_room_list(payload)
    ActionCable.server.broadcast room_list_stream_name, payload
  end

  def room_list_stream_name
    AnyCable::Rails.stream_name_from([ self, :room_list ])
  end

  def signed_room_list_stream_name
    AnyCable::Rails.signed_stream_name([ self, :room_list ])
  end

  private
    def accent_must_be_shipped
      unless settings.accent.in?(ACCENTS)
        errors.add(:settings, "accent must be one of: #{ACCENTS.join(", ")}")
      end
    end

    def invite_links_disabled?
      saved_change_to_settings? && !settings.allow_users_to_create_invite_links?
    end

    def invalidate_personal_invite_links
      join_codes.personal.destroy_all
    end

    def sync_name_to_workspace
      return unless Sabha.saas?
      return unless ApplicationRecord.current_tenant.present?

      Workspace
        .find_by(external_id: ApplicationRecord.current_tenant)
        &.update_column(:name, name)
    end

    def sync_logo_to_workspace
      return unless Sabha.saas?
      return unless ApplicationRecord.current_tenant.present?

      Workspace
        .find_by(external_id: ApplicationRecord.current_tenant)
        &.update_column(:has_logo, logo.attached?)
    end
end
