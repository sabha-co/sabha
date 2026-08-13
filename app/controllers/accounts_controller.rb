class AccountsController < ApplicationController
  before_action :ensure_can_administer, only: %i[edit update]
  before_action :set_account

  def show
    @member_count = User.without_bots.active.verified.count
    @room_count = Room.where(type: %w[Rooms::Open Rooms::Closed Rooms::Forum]).count
  end

  def edit
  end

  def update
    @account.attach_logo(account_params[:logo]) if account_params[:logo].present?
    @account.update!(merged_account_params.except(:logo))
    redirect_back fallback_location: edit_account_url, notice: "✓"
  rescue Account::InvalidLogoType
    redirect_back fallback_location: edit_account_url, alert: "Logo must be a JPEG, PNG, GIF, or WebP image"
  end

  private
    def set_account
      @account = Current.account
    end

    def account_params
      params.require(:account).permit(
        :name, :logo, :email_notifications_enabled, :weekly_digest_enabled,
        settings: %i[
          restrict_room_creation_to_administrators
          restrict_direct_messages_to_administrators
          allow_users_to_create_invite_links
          accent
        ]
      )
    end

    def merged_account_params
      permitted = account_params
      if permitted[:settings].present?
        # Filter the stored JSON to keys the current schema still knows about
        # before merging. Older rows can carry keys that have since been
        # removed from `has_json :settings` on Account; without this filter,
        # the merge would re-submit them through `settings=`, which iterates
        # via `assign_data_with_type_casting` and raises NoMethodError on the
        # first unknown setter. Saving once heals the row.
        existing_settings = (@account.read_attribute(:settings) || {}).select do |key, _|
          @account.settings.respond_to?("#{key}=")
        end
        permitted[:settings] = existing_settings.merge(permitted[:settings])
      end
      permitted
    end
end
