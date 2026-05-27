class Account < ApplicationRecord
  include Joinable, Account::Storage

  VALID_AUTH_METHODS = %w[password otp sso].freeze
  ALLOWED_LOGO_CONTENT_TYPES = %w[ image/jpeg image/png image/gif image/webp ].freeze
  MAX_LOGO_SIZE = 5.megabytes

  has_one_attached :logo, dependent: :purge_later
  has_json :settings, restrict_room_creation_to_administrators: false, restrict_direct_messages_to_administrators: false, allow_users_to_create_invite_links: true

  validate :acceptable_logo, if: :logo_attached?

  after_save :invalidate_personal_invite_links, if: :invite_links_disabled?
  after_commit :sync_name_to_workspace, if: :saved_change_to_name?
  after_save_commit :sync_logo_to_workspace

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

  def purge_logo
    logo.purge
    sync_logo_to_workspace
  end

  private
    def logo_attached?
      logo.attached?
    end

    def acceptable_logo
      unless ALLOWED_LOGO_CONTENT_TYPES.include?(logo.content_type)
        errors.add(:logo, "must be a JPEG, PNG, GIF, or WebP image")
        return
      end

      if logo.byte_size > MAX_LOGO_SIZE
        errors.add(:logo, "is too large (max #{MAX_LOGO_SIZE / 1.megabyte}MB)")
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
