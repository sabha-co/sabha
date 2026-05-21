class Inboxes::ClearancesController < InboxesController
  skip_before_action :set_sidebar_memberships

  def create
    if params[:scope] == "direct_messages"
      Current.user.mark_direct_messages_as_read(session[:inbox_last_loaded_dms_created_at])
    else
      Current.user.mark_inbox_as_read(
        messages_loaded_at:      session[:inbox_last_loaded_message_created_at],
        notifications_loaded_at: session[:inbox_last_loaded_notification_created_at],
        activity_loaded_at:      session[:inbox_last_loaded_activity_created_at]
      )
    end

    redirect_back(fallback_location: inbox_activity_index_path) unless params[:stay]
  end
end
