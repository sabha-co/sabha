class AccountsController < ApplicationController
  before_action :ensure_can_administer, only: %i[edit update]
  before_action :set_account

  def edit
    users = account_users.includes(avatar_attachment: :blob).ordered
    @administrators, @members = users.partition(&:administrator?)
    set_page_and_extract_portion_from users, per_page: 500
  end

  def update
    @account.update!(merged_account_params)
    redirect_to edit_account_url, notice: "✓"
  end

  private
    def set_account
      @account = Current.account
    end

    def account_params
      params.require(:account).permit(:name, :logo, :auth_method, settings: {})
    end

    def merged_account_params
      permitted = account_params
      if permitted[:settings].present?
        existing_settings = @account.read_attribute(:settings) || {}
        permitted[:settings] = existing_settings.merge(permitted[:settings])
      end
      permitted
    end

    def account_users
      if Current.user.can_administer?
        User.where(status: [ :active, :banned ])
      else
        User.active
      end
    end
end
