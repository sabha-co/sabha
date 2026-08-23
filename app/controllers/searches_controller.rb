class SearchesController < ApplicationController
  before_action :set_messages, only: %i[ index page ]

  layout false, only: %i[ page ]

  def index
    @query = query if query.present?
    @recent_searches = Current.user.searches.global.ordered
    @return_to_room = last_room_visited
    @message_count = messages.count
  end

  def create
    Current.user.searches.record(query)
    redirect_to searches_url(q: query)
  end

  def clear
    Current.user.searches.global.destroy_all
    redirect_to searches_url
  end

  def page
    head :no_content if @messages.blank?
  end

  private
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
        Current.user.reachable_messages.search(query)
      else
        Message.none
      end
    end

    def query
      Message::SearchIndex.normalize(params[:q])
    end
end
