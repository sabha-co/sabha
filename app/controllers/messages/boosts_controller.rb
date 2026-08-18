class Messages::BoostsController < ApplicationController
  include NotifyBots

  before_action :set_message

  def index
  end

  def new
  end

  def create
    @boost = @message.boosts.create(boost_params)
    notify_bots(@boost, :created) if @boost.persisted?
    # Fall through to render the grouped frame even on a duplicate, so a client
    # that missed the original response/broadcast converges on retry.
  rescue ActiveRecord::RecordNotUnique
    render :create
  end

  def destroy
    # A grouped chip toggles off by content (it can't carry a per-viewer boost
    # id); the id form stays for anywhere that still deletes a specific boost.
    @boost = boost_to_remove
    @boost&.destroy!
    notify_bots(@boost, :deleted) if @boost
    # Render the current frame regardless — a delete that found nothing still
    # returns authoritative state so a stale client repairs itself.
  end

  private
    def set_message
      @message = Current.user.reachable_message(params[:message_id])
    end

    def boost_to_remove
      if params[:content].present?
        Current.user.boosts.find_by(message: @message, content: params[:content])
      else
        Current.user.boosts.find_by(id: params[:id])
      end
    end

    def boost_params
      params.require(:boost).permit(:content)
    end
end
