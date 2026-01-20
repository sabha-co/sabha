class Messages::BookmarksController < ApplicationController
  before_action :set_message

  def create
    @bookmark = @message.bookmarks.find_or_create_by(user: Current.user)

    broadcast_message_update
  end

  def destroy
    Current.user.bookmarks.where(message: @message).find_each(&:deactivate!)

    broadcast_message_update
    broadcast_remove_from_bookmarks_inbox
  end

  private
    def set_message
      @message = Current.user.reachable_messages.find(params[:message_id])
    end

    def broadcast_message_update
      html = render_to_string(partial: "messages/actions/bookmark", locals: { message: @message })
      @message.broadcast_replace_to Current.user, @message.room, :messages, target: [ @message, :bookmarking ], html: html
      @message.broadcast_replace_to Current.user, :inbox, target: [ @message, :bookmarking ], html: html

      indicator_html = render_to_string(partial: "messages/actions/bookmark_indicator", locals: { message: @message })
      @message.broadcast_replace_to Current.user, @message.room, :messages, target: [ @message, :bookmark_indicator ], html: indicator_html
      @message.broadcast_replace_to Current.user, :inbox, target: [ @message, :bookmark_indicator ], html: indicator_html
    end

    def broadcast_remove_from_bookmarks_inbox
      @message.broadcast_remove_to Current.user, :inbox_bookmarks
    end
end
