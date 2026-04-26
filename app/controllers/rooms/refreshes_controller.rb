class Rooms::RefreshesController < ApplicationController
  include RoomScoped

  before_action :set_last_updated_at
  before_action :set_unread_at_message

  def show
    respond_to do |format|
      format.turbo_stream do
        @new_messages = @room.messages.for_display.with_bookmark_status_for(Current.user).page_created_since(@last_updated_at).to_a
        @updated_messages = @room.messages.for_display.with_bookmark_status_for(Current.user).without(@new_messages).page_updated_since(@last_updated_at).to_a

        Message.with_thread_participants(@new_messages + @updated_messages)
      end
      format.html { redirect_to @room }
    end
  end

  private
    def set_last_updated_at
      @last_updated_at = Time.at(0, params[:since].to_i, :millisecond)
    end

    def set_unread_at_message
      return if params[:unread_at_message_id].blank?

      @unread_at_message = Message.find_by(id: params[:unread_at_message_id])
    end
end
