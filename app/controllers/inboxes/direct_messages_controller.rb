class Inboxes::DirectMessagesController < ApplicationController
  include InboxScoped

  before_action :set_channel_pagination_anchors, if: :paginating?

  def index
    if paginating?
      @memberships = paginate(Inbox::DirectMessagesQuery.new(Current.user).call)
      return head(:no_content) if @memberships.empty?

      @direct_channel_members = Channels::Direct.members_for_display_by_channel(
        @memberships.map(&:channel_id), excluding: Current.user
      )
      render partial: "items"
    else
      session[:inbox_last_loaded_dms_created_at] = Time.current.iso8601
      load_dm_inbox
    end
  end

  private
    def set_channel_pagination_anchors
      @before = Channel.active.find_by(id: params[:before])
      @after = Channel.active.find_by(id: params[:after])
    end

    def load_dm_inbox
      @memberships = Inbox::DirectMessagesQuery.new(Current.user).call.last_page
      @direct_channel_members = Channels::Direct.members_for_display_by_channel(
        @memberships.map(&:channel_id), excluding: Current.user
      )
    end
end
