class API::Bots::SearchesController < API::Bots::BaseController
  include ActiveStorage::SetCurrent, CursorPaginated

  before_action :parse_pagination_params, only: :show

  def show
    query = sanitize_query(params[:q])
    return render_validation_error("Query parameter 'q' is required") if query.blank?

    room_ids = Array(params[:room_ids])
    author_ids = Array(params[:author_ids])

    scope = Current.user.reachable_messages.active.search(query)
              .reorder(created_at: :desc, id: :desc)
    scope = scope.in_rooms(room_ids) if room_ids.any?
    scope = scope.created_by(author_ids) if author_ids.any?
    scope = scope.since(@after_time) if @after_time
    scope = if @before_id
      scope.before_cursor(@before_time, @before_id)
    elsif @before_time
      scope.created_before(@before_time)
    else
      scope
    end
    scope = scope.with_rich_text_body_and_embeds.with_creator.includes(:room).limit(@limit + 1)

    messages = scope.to_a
    @has_more = messages.size > @limit
    @messages = messages.first(@limit)
    @next_cursor = build_cursor(@messages.last) if @has_more
  end

  private
    def sanitize_query(value)
      value.to_s.gsub(/[^[:word:]]/, " ").strip
    end
end
