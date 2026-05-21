class InboxesController < ApplicationController
  def show
    session.delete :inbox_last_loaded_activity_created_at
    session.delete :inbox_last_loaded_notification_created_at
    session.delete :inbox_last_loaded_message_created_at

    redirect_to inbox_activity_index_path
  end
end
