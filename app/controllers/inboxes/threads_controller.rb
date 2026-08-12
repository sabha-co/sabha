class Inboxes::ThreadsController < ApplicationController
  include InboxScoped

  before_action :set_message_pagination_anchors, if: :paginating?

  def index
    @messages = find_messages_with(Inbox::ThreadsQuery)
    @thread_unread = Inbox::ThreadsQuery.unseen_reply_counts(Current.user, @messages)

    render partial: "items" if paginating?
  end
end
