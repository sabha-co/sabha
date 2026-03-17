class Accounts::BadgesController < ApplicationController
  before_action :ensure_can_administer
  before_action :set_badge, only: %i[update destroy]

  def index
    @badges = Badge.ordered.includes(:users)
  end

  def create
    @badge = Badge.new(badge_params)

    if @badge.save
      redirect_to account_badges_url
    else
      redirect_to account_badges_url, alert: @badge.errors.full_messages.join(", ")
    end
  end

  def update
    if @badge.update(badge_params)
      redirect_to account_badges_url
    else
      redirect_to account_badges_url, alert: @badge.errors.full_messages.join(", ")
    end
  end

  def destroy
    @badge.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@badge) }
      format.html { redirect_to account_badges_url, status: :see_other }
    end
  end

  private
    def set_badge
      @badge = Badge.find(params[:id])
    end

    def badge_params
      params.require(:badge).permit(:name, :icon, :color)
    end
end
