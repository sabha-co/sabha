class Accounts::CustomStylesController < ApplicationController
  before_action :ensure_can_administer, :set_account

  def edit
  end

  def update
    @account.update!(account_params)
    redirect_to edit_account_custom_styles_url, notice: "✓"
  end

  private
    def set_account
      @account = Current.account
    end

    def account_params
      params.require(:account).permit(:custom_styles)
    end
end
