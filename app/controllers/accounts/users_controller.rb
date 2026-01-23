class Accounts::UsersController < ApplicationController
  include NotifyBots

  before_action :ensure_can_administer
  before_action :set_user, only: %i[update destroy reactivate]

  def index
    @badges = Badge.ordered.includes(:users).to_a
    @total_members = User.without_bots.active.count

    if searching?
      search_users
    elsif filtering_banned?
      load_banned_users
    elsif filtering_deactivated?
      load_deactivated_users
    else
      load_members_by_role
    end
  end

  def update
    @user.update(user_params)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to account_users_url }
    end
  end

  def destroy
    @user.deactivate
    deliver_webhooks_to_bots(@user, :deleted)
    redirect_to account_users_url
  end

  def reactivate
    if @user.reactivatable_by?(Current.user)
      @user.reactivate
    end
    redirect_to account_users_url
  end

  private
    def set_user
      @user = User.find(params[:user_id] || params[:id])
    end

    def user_params
      params.require(:user).permit(:role, :badge_id).tap do |permitted|
        permitted.delete(:role) unless permitted[:role].in?(%w[member moderator administrator])
      end
    end

    def searching?
      params[:query].present?
    end

    def filtering_banned?
      params[:status] == "banned"
    end

    def filtering_deactivated?
      params[:status] == "deactivated"
    end

    def users_scope
      User.without_bots.includes(:badge, avatar_attachment: :blob).ordered
    end

    def search_users
      @searching = true
      query = params[:query].to_s.strip
      @users = users_scope.active.where("name LIKE ?", "%#{User.sanitize_sql_like(query)}%").limit(50)
    end

    def load_banned_users
      @filtering_banned = true
      @users = users_scope.banned
    end

    def load_deactivated_users
      @filtering_deactivated = true
      @users = users_scope.deactivated
    end

    def load_members_by_role
      scope = users_scope.active
      @administrators = scope.where(role: :administrator).to_a
      @moderators = scope.where(role: :moderator).to_a

      members = scope.where(role: :member)
      set_page_and_extract_portion_from members, per_page: 25
      @members = @page.records

      @deactivated_count = User.without_bots.deactivated.count
      @banned_count = User.without_bots.banned.count
    end
end
