module CursorPaginated
  extend ActiveSupport::Concern

  MAX_LIMIT = 200
  DEFAULT_LIMIT = 50

  private
    # Reads `before`, `after`, and `limit` from params and exposes them as
    # `@before_time`, `@before_id`, `@after_time`, `@limit`. Renders 422 and
    # halts the action chain on unparseable timestamps. Wire this in via
    # `before_action :parse_pagination_params, only: [...]`.
    def parse_pagination_params
      @before_time, @before_id = parse_before(params[:before])
      return render_validation_error("'before' must be ISO8601 timestamp or composite cursor") if params[:before].present? && @before_time.nil?

      @after_time = parse_time(params[:after])
      return render_validation_error("'after' must be an ISO8601 timestamp") if params[:after].present? && @after_time.nil?

      @limit = (params[:limit].presence || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
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
