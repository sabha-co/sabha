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
      @messages = Message.with_thread_participants(find_paged_messages)
    end

    def find_paged_messages
      base = messages.with_creator.with_thread_summary.with_bookmark_status_for(Current.user)
      case
      when params[:before].present?
        base.page_before(messages.find(params[:before]))
      when params[:after].present?
        base.page_after(messages.find(params[:after]))
      else
        base.last_page
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
