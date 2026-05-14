class AccountsController < ApplicationController
  before_action :ensure_can_administer, only: %i[update]
  before_action :set_account

  def edit
    unless Current.user.can_administer?
      @member_count = User.without_bots.active.verified.count
      @room_count = Room.where(type: %w[Rooms::Open Rooms::Closed]).count
    end
  end

  def update
    @account.attach_logo(account_params[:logo]) if account_params[:logo].present?
    @account.update!(merged_account_params.except(:logo))
    redirect_to edit_account_url, notice: "✓"
  rescue Account::InvalidLogoType
    redirect_to edit_account_url, alert: "Logo must be a JPEG, PNG, GIF, or WebP image"
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
        ]
      )
    end

    def merged_account_params
      permitted = account_params
      if permitted[:settings].present?
        existing_settings = @account.read_attribute(:settings) || {}
        permitted[:settings] = existing_settings.merge(permitted[:settings])
      end
      permitted
    end
end
