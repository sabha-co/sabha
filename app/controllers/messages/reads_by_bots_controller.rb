class Messages::ReadsByBotsController < ApplicationController
  include ActiveStorage::SetCurrent

  skip_forgery_protection
  allow_bot_access only: :index
  rescue_from ActiveRecord::RecordNotFound, with: :room_not_found

  def index
    @room = Current.user.rooms.find(params[:room_id])
    # last(50) generates LIMIT SQL; reverse restores chronological order
    messages = @room.messages.active.with_creator.with_attached_attachment.ordered.last(50).reverse

    render json: messages.map { |msg|
      { id: msg.id,
        creator: { id: msg.creator.id, name: msg.creator.name },
        body: { html: msg.body.body.to_s, plain: msg.plain_text_body },
        has_attachment: msg.attachment?,
        attachment: msg.attachment? ? attachment_json(msg) : nil,
        mentionees: msg.mentionees.map { |m| { id: m.id, name: m.name } },
        created_at: msg.created_at.iso8601 }
    }
  end

  private
    def attachment_json(message)
      blob = message.attachment.blob
      {
        url: blob.url(expires_in: 1.hour),
        filename: blob.filename.to_s,
        content_type: blob.content_type,
        byte_size: blob.byte_size
      }
    end

    def room_not_found
      render json: { error: "Room not found", code: "room_not_found" }, status: :not_found
    end
end
