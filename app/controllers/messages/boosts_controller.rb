class Messages::BoostsController < ApplicationController
  include NotifyBots

  before_action :set_message

  def index
  end

  def new
  end

  def create
    @boost = @message.boosts.create(boost_params)
    return head :ok unless @boost.persisted?

    notify_bots(@boost, :created)
  rescue ActiveRecord::RecordNotUnique
    head :ok
  end

  def destroy
    @boost = Current.user.boosts.find(params[:id])
    @boost.destroy!

    notify_bots(@boost, :deleted)
  end

  private
    def set_message
      @message = Current.user.reachable_messages.find(params[:message_id])
    end

    def boost_params
      params.require(:boost).permit(:content)
    end
end
