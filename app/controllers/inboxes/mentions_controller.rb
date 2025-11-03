class Inboxes::MentionsController < InboxesController
  before_action :set_message_pagination_anchors

  layout false

  def index
    @messages = find_mentions

    render "inboxes/messages/index"
  end
end
