class Accounts::UsersController < ApplicationController
  include NotifyBots

  before_action :ensure_can_administer, :set_user, only: %i[ update destroy ]

  def index
    set_page_and_extract_portion_from User.active.ordered.without_bots, per_page: 500
  end

  def update
    @user.update(role_params)
    redirect_to request.referer || user_url(@user), notice: "✓"
  end

  def destroy
    @user.deactivate
    deliver_webhooks_to_bots(@user, :deleted)
    redirect_to edit_account_url
  end

  private
    def set_user
      @user = User.active.find(params[:user_id] || params[:id])
    end

    def role_params
      { role: params.require(:user)[:role].presence_in(%w[ member expert administrator ]) || "member" }
    end
end
