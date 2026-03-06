class Account < ApplicationRecord
  include Joinable, Account::Storage

  VALID_AUTH_METHODS = %w[password otp].freeze

  has_one_attached :logo
  has_json :settings, restrict_room_creation_to_administrators: false, restrict_direct_messages_to_administrators: false, allow_users_to_create_invite_links: true

  after_save :invalidate_personal_invite_links, if: :invite_links_disabled?

  # Auth method is controlled via ENV["AUTH_METHOD"]
  # Valid values: "password" (default), "otp"
  def auth_method_value
    value = ENV["AUTH_METHOD"] || "password"
    value.in?(VALID_AUTH_METHODS) ? value : "password"
  end

  def attach_logo(blob)
    logo.attach(blob)
    touch
    sync_logo_to_workspace
  end

  def purge_logo
    logo.purge
    touch
    sync_logo_to_workspace
  end

  private
    def invite_links_disabled?
      saved_change_to_settings? && !settings.allow_users_to_create_invite_links?
    end

    def invalidate_personal_invite_links
      join_codes.personal.destroy_all
    end

    def sync_logo_to_workspace
      return unless Sabha.saas?
      return unless ApplicationRecord.current_tenant.present?

      Workspace
        .find_by(external_id: ApplicationRecord.current_tenant)
        &.update_column(:has_logo, logo.attached?)
    end
end
