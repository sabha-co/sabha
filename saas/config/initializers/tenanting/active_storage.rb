# frozen_string_literal: true

# Active Storage URL Options for Multi-Tenancy
#
# Sets ActiveStorage::Current.url_options with script_name
# so attachment URLs include the workspace prefix.
#
# Without this:
#   image.url → /rails/active_storage/blobs/.../image.jpg
#
# With this:
#   image.url → /1000001/rails/active_storage/blobs/.../image.jpg

return unless Sabha.saas?

# Use proxy mode for ActiveStorage in SaaS mode
# This serves files through Rails instead of redirecting to disk URLs,
# which maintains the tenant context for file serving.
Rails.application.config.active_storage.resolve_model_to_route = :rails_storage_proxy

# Install on ActionController::Base via load hook so the controller is patched
# at its natural load time (covers ApplicationController + ActiveStorage::BaseController
# via inheritance, and avoids triggering the load hook prematurely during boot).
ActiveSupport.on_load(:action_controller_base) do
  before_action :set_active_storage_url_options

  private
    def set_active_storage_url_options
      ActiveStorage::Current.url_options = {
        protocol: request.protocol,
        host: request.host,
        port: request.port,
        script_name: request.script_name
      }
    end
end
