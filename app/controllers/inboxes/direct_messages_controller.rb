class Inboxes::DirectMessagesController < InboxesController
  before_action :set_room_pagination_anchors

  def index
    if paginating?
      @memberships = paginate(Inbox::DirectMessagesQuery.new(Current.user).call)
      return head(:no_content) if @memberships.empty?

      @direct_room_members = Rooms::Direct.members_for_display_by_room(
        @memberships.map(&:room_id), excluding: Current.user
      )
      render partial: "list"
    else
      session[:inbox_last_loaded_dms_created_at] = Time.current.iso8601
      load_dm_sidebar
    end
  end

  private
    def set_room_pagination_anchors
      @before = Room.active.find_by(id: params[:before])
      @after = Room.active.find_by(id: params[:after])
    end

    def load_dm_sidebar
      sidebar = SidebarMemberships.new(Current.user)
      @memberships = Inbox::DirectMessagesQuery.new(Current.user).call.last_page
      @direct_memberships = sidebar.direct
      room_ids = (@memberships.map(&:room_id) + @direct_memberships.map(&:room_id)).uniq
      @direct_room_members = Rooms::Direct.members_for_display_by_room(room_ids, excluding: Current.user)
    end
end
