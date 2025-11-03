module RackMiniProfilerAuthorization
  extend ActiveSupport::Concern

  included do
    before_action :authorize_rack_mini_profiler
  end

  private
    def authorize_rack_mini_profiler
      Rack::MiniProfiler.authorize_request if authorize_rack_mini_profiler?
    end

    def authorize_rack_mini_profiler?
      return true if Rails.env.development?
      return true if Rails.env.production? && signed_in? && Current.user.can_administer?
      false
    end
end
