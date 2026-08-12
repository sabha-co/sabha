class Inboxes::ThreadsController < ApplicationController
  include InboxScoped

  before_action :set_message_pagination_anchors, if: :paginating?

  def index
    @messages = find_messages_with(Inbox::ThreadsQuery)
    @thread_unread = Inbox::ThreadsQuery.unseen_reply_counts(Current.user, @messages)

    if paginating?
      render partial: "items"
    else
      @followed_thread_count = Inbox::ThreadsQuery.new(Current.user).call.except(:order).count
    end
  end
end
