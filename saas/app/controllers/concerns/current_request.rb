# frozen_string_literal: true

module CurrentRequest
  extend ActiveSupport::Concern

  # Captures request metadata into Current attributes
  # Used for logging, auditing, and session creation

  included do
    before_action :set_current_request_attributes
  end

  private

    def set_current_request_attributes
      Current.request = request
    end
end
