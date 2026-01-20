class Messages::BookmarksController < ApplicationController
  before_action :set_message

  def create
    @bookmark = @message.bookmarks.find_or_create_by(user: Current.user)

    broadcast_message_update
  end

  def destroy
    Current.user.bookmarks.find_by(message: @message)&.deactivate!

    broadcast_message_update
  end

  private
    def set_message
      @message = Current.user.reachable_messages.find(params[:message_id])
    end

    def broadcast_message_update
      html = render_to_string(partial: "messages/actions/bookmark", locals: { message: @message })
      @message.broadcast_replace_to Current.user, @message.room, :messages, target: [ @message, :bookmarking ], html: html
      @message.broadcast_replace_to Current.user, :inbox, target: [ @message, :bookmarking ], html: html
    end
end
