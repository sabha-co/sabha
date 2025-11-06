class Inboxes::AnswersController < InboxesController
  before_action :set_message_pagination_anchors
  before_action :ensure_is_expert

  layout false

  def index
    @messages = find_answers

    render "inboxes/messages/index"
  end
end
