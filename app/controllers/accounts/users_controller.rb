class Accounts::UsersController < ApplicationController
  include NotifyBots

  before_action :ensure_can_administer, only: %i[edit update destroy]
  before_action :set_user, only: %i[edit update destroy]
  before_action :load_status_counts, only: :index, if: -> { Current.user.staff? }

  def index
    @member_count = User.without_bots.active.verified.count

    if searching?
      search_users
    elsif Current.user.staff? && filtering_banned?
      load_banned_users
    elsif Current.user.staff? && filtering_deactivated?
      load_deactivated_users
    else
      load_members_by_role
    end
  end

  def edit
    return redirect_to account_users_url unless @user.manageable_by?(Current.user)

    @badges = Badge.ordered.to_a
  end

  def update
    @user.update!(user_params)
    @notice = role_change_notice if @user.saved_change_to_role?

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to account_users_url, notice: @notice }
    end
  end

  def destroy
    return redirect_to account_users_url, alert: "You can't deactivate yourself." unless @user.removable_by?(Current.user)

    @user.deactivate
    notify_bots(@user, :deleted)

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@user) }
      format.html { redirect_to account_users_url }
    end
  end

  private
    def role_change_notice
      "#{@user.name} is now #{@user.role.humanize(capitalize: false)}"
    end

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

    def bots_scope
      User.active_bots.includes(avatar_attachment: :blob)
    end

    def search_users
      @searching = true
      query = params[:query].to_s.strip
      pattern = "%#{User.sanitize_sql_like(query)}%"
      # matches renders ILIKE on Postgres, LIKE on SQLite — case-insensitive on both.
      name_matches = User.arel_table[:name].matches(pattern)
      people_scope = Current.user.staff? ? users_scope : users_scope.active
      people = people_scope.where(name_matches)
      bots = bots_scope.where(name_matches)
      @users = (people + bots).first(50)
      preload_activity(@users)
      @users = sort_by_activity(@users)
    end

    def load_banned_users
      @filtering_banned = true
      @users = users_scope.banned
      preload_activity(@users)
    end

    def load_deactivated_users
      @filtering_deactivated = true
      @users = users_scope.deactivated
      preload_activity(@users)
    end

    def load_members_by_role
      scope = users_scope.active
      @administrators = scope.where(role: :administrator).to_a
      @moderators = scope.where(role: :moderator).to_a

      members = scope.where(role: :member)
      set_page_and_extract_portion_from members, per_page: 25
      @members = @page.records

      preload_activity(@administrators + @moderators + @members)

      @administrators = sort_by_activity(@administrators)
      @moderators = sort_by_activity(@moderators)
      @members = sort_by_activity(@members)

      @bots = bots_scope.ordered.to_a
    end

    def load_status_counts
      @deactivated_count = User.without_bots.deactivated.count
      @banned_count = User.without_bots.banned.count
    end

    ACTIVITY_SORT_ORDER = { active: 0, away: 1, offline: 2 }.freeze

    def preload_activity(users)
      @activity_statuses = Membership.activity_statuses_for(users.map(&:id))
      @activity_statuses[Current.user.id] = :active # You're viewing the page, so you're online
    end

    def sort_by_activity(users)
      users.sort_by { |u| ACTIVITY_SORT_ORDER.fetch(@activity_statuses[u.id], 2) }
    end
end
