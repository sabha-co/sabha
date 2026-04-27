class API::Bots::SearchesController < API::Bots::BaseController
  include ActiveStorage::SetCurrent

  MAX_LIMIT = 200
  DEFAULT_LIMIT = 50

  def show
    query = sanitize_query(params[:q])
    return render_validation_error("Query parameter 'q' is required") if query.blank?

    before_time, before_id = parse_before(params[:before])
    return render_validation_error("'before' must be ISO8601 timestamp or composite cursor") if params[:before].present? && before_time.nil?

    after_time = parse_time(params[:after])
    return render_validation_error("'after' must be an ISO8601 timestamp") if params[:after].present? && after_time.nil?

    @limit = (params[:limit].presence || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)

    room_ids = Array(params[:room_ids])
    author_ids = Array(params[:author_ids])

    scope = Current.user.reachable_messages.active.search(query)
              .reorder(created_at: :desc, id: :desc)
    scope = scope.in_rooms(room_ids) if room_ids.any?
    scope = scope.created_by(author_ids) if author_ids.any?
    scope = scope.since(after_time) if after_time
    scope = if before_id
      scope.before_cursor(before_time, before_id)
    elsif before_time
      scope.created_before(before_time)
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

    # Accepts either a plain ISO8601 timestamp (filter intent) or
    # a composite "<iso>|<id>" cursor (pagination intent).
    def parse_before(value)
      return [ nil, nil ] if value.blank?
      time_str, id_str = value.to_s.split("|", 2)
      time = Time.zone.iso8601(time_str)
      id = id_str.present? ? Integer(id_str) : nil
      [ time, id ]
    rescue ArgumentError, TypeError
      [ nil, nil ]
    end

    def parse_time(value)
      return nil if value.blank?
      Time.zone.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def build_cursor(message)
      "#{message.created_at.iso8601}|#{message.id}"
    end

    def render_validation_error(message)
      render json: { error: message, code: "validation_failed" }, status: :unprocessable_entity
    end
end
