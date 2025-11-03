module VersionHeaders
  extend ActiveSupport::Concern

  included do
    before_action :set_version_headers
  end

  private
    def set_version_headers
      response.headers["X-Version"] = Rails.application.config.app_version
      response.headers["X-Rev"] = Rails.application.config.git_revision
    end
end
