class Inboxes::DirectMessagesController < InboxesController
  before_action :set_room_pagination_anchors, only: :index

  layout false

  def index
    @memberships = paginate(Inbox::DirectMessagesQuery.new(Current.user).call)
    @direct_room_members = Rooms::Direct.members_for_display_by_room(
      @memberships.map(&:room_id),
      excluding: Current.user
    )

    if @memberships.empty?
      head :no_content
    else
      render "inboxes/direct_messages/index"
    end
  end

  private

  def set_room_pagination_anchors
    @before = Room.active.find_by(id: params[:before])
    @after = Room.active.find_by(id: params[:after])
  end
end
