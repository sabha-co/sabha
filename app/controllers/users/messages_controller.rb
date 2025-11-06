class Users::MessagesController < ApplicationController
  before_action :set_user
  before_action :set_messages

  layout false, only: %i[ page ]

  def index
    @query = query.presence
    @recent_searches = Current.user.searches.for_creator(@user).ordered
    @return_to_room = last_room_visited
    @message_count = messages.count
  end

  def page
    head :no_content if @messages.blank?
  end

  private
    def set_user
      @user = User.find(params[:user_id])
    end

    def set_messages
      @messages = Bookmark.populate_for(find_paged_messages)
    end

    def find_paged_messages
      case
      when params[:before].present?
        messages.with_creator.page_before(messages.find(params[:before]))
      when params[:after].present?
        messages.with_creator.page_after(messages.find(params[:after]))
      else
        messages.with_creator.last_page
      end
    end

    def messages
      if query.present?
        Current.user.reachable_messages.created_by(@user).search(query)
      else
        Current.user.reachable_messages.created_by(@user)
      end
    end

    def query
      params[:q]&.gsub(/[^[:word:]]/, " ")
    end
end
