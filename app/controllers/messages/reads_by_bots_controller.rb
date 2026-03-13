class Messages::ReadsByBotsController < ApplicationController
  skip_forgery_protection
  allow_bot_access only: :index
  rescue_from ActiveRecord::RecordNotFound, with: :room_not_found

  def index
    @room = Current.user.rooms.find(params[:room_id])
    # last(50) generates LIMIT SQL; reverse restores chronological order
    messages = @room.messages.active.with_creator.ordered.last(50).reverse

    render json: messages.map { |msg|
      { id: msg.id,
        creator: { id: msg.creator.id, name: msg.creator.name },
        body: { html: msg.body.body.to_s, plain: msg.plain_text_body },
        mentionees: msg.mentionees.map { |m| { id: m.id, name: m.name } },
        created_at: msg.created_at.iso8601 }
    }
  end

  private
    def room_not_found
      render json: { error: "Room not found", code: "room_not_found" }, status: :not_found
    end
end
