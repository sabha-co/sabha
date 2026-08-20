class Accounts::BadgesController < ApplicationController
  before_action :ensure_can_manage_account
  before_action :set_badge, only: %i[ edit update destroy ]

  def index
    @badges = Badge.ordered.includes(:users)
  end

  def new
    @badge = Badge.new
  end

  def edit
  end

  def create
    @badge = Badge.new(badge_params)

    if @badge.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to account_badges_url, notice: "#{@badge.name} created" }
      end
    else
      render :new, status: :unprocessable_entity, formats: :html
    end
  end

  def update
    if @badge.update(badge_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to account_badges_url, notice: "#{@badge.name} updated" }
      end
    else
      render :edit, status: :unprocessable_entity, formats: :html
    end
  end

  def destroy
    @badge.destroy!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to account_badges_url, status: :see_other, notice: "#{@badge.name} removed" }
    end
  end

  private
    def set_badge
      @badge = Badge.find(params[:id])
    end

    def badge_params
      params.require(:badge).permit(:name, :color)
    end
end
