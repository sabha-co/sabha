module CursorPaginated
  extend ActiveSupport::Concern

  MAX_LIMIT = 200
  DEFAULT_LIMIT = 50

  private
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
