class Messages::Boosts::ByBotsController < ApplicationController
  include NotifyBots

  skip_forgery_protection
  allow_bot_access only: %i[create destroy]
  before_action :require_bot_authentication
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def create
    @room = Current.user.rooms.find(params[:room_id])
    @message = @room.messages.active.find(params[:message_id])

    content = request.body.tap(&:rewind).read.force_encoding("UTF-8").strip
    @boost = @message.boosts.create!(content: content, booster: Current.user)

    deliver_webhooks_to_bots(@boost, :created)

    render json: { id: @boost.id, content: @boost.content }, status: :created
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    render json: { error: "Boost already exists or is invalid", code: "validation_failed" }, status: :unprocessable_entity
  end

  def destroy
    @room = Current.user.rooms.find(params[:room_id])
    @message = @room.messages.active.find(params[:message_id])
    @boost = @message.boosts.where(booster: Current.user).find(params[:id])

    @boost.destroy!
    deliver_webhooks_to_bots(@boost, :deleted)

    head :no_content
  end

  private
    def require_bot_authentication
      head :forbidden unless authenticated_by.bot_key?
    end

    def not_found
      render json: { error: "Room, message, or boost not found", code: "not_found" }, status: :not_found
    end
end
