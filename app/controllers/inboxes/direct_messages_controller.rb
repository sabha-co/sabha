class Inboxes::DirectMessagesController < ApplicationController
  include InboxScoped, DirectMessageListable

  before_action :set_room_pagination_anchors, if: :paginating?

  def index
    if paginating?
      @memberships = paginate(Inbox::DirectMessagesQuery.new(Current.user).call)
      return head(:no_content) if @memberships.empty?

      @direct_room_members = Rooms::Direct.members_for_display_by_room(
        @memberships.map(&:room_id), excluding: Current.user
      )
      @direct_member_statuses = direct_member_statuses(@direct_room_members)
      render partial: "items"
    else
      session[:inbox_last_loaded_dms_created_at] = Time.current.iso8601
      load_dm_conversations
    end
  end

  private
    def set_room_pagination_anchors
      @before = Room.active.find_by(id: params[:before])
      @after = Room.active.find_by(id: params[:after])
    end
end
