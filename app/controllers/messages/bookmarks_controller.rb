class Messages::BookmarksController < ApplicationController
  before_action :set_message

  def create
    @bookmark = @message.bookmarks.find_or_create_by(user: Current.user)

    broadcast_message_update
  end

  def destroy
    Current.user.bookmarks.find_by(message: @message)&.destroy!

    broadcast_message_update
    broadcast_remove_from_bookmarks_inbox
  end

  private
    def set_message
      @message = Current.user.reachable_message(params[:message_id])
    end

    def broadcast_message_update
      @message.broadcast_replace_to Current.user, @message.room, :messages,
        target: [ @message, :bookmarking ], partial: "messages/actions/bookmark", locals: { message: @message }
      @message.broadcast_replace_to Current.user, :inbox,
        target: [ @message, :bookmarking ], partial: "messages/actions/bookmark", locals: { message: @message }

      @message.broadcast_replace_to Current.user, @message.room, :messages,
        target: [ @message, :bookmark_indicator ], partial: "messages/actions/bookmark_indicator", locals: { message: @message }
      @message.broadcast_replace_to Current.user, :inbox,
        target: [ @message, :bookmark_indicator ], partial: "messages/actions/bookmark_indicator", locals: { message: @message }
    end

    def broadcast_remove_from_bookmarks_inbox
      @message.broadcast_remove_to Current.user, :inbox_bookmarks
    end
end
