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

return unless Campfire.saas?

# Use proxy mode for ActiveStorage in SaaS mode
# This serves files through Rails instead of redirecting to disk URLs,
# which maintains the tenant context for file serving.
Rails.application.config.active_storage.resolve_model_to_route = :rails_storage_proxy

Rails.application.config.to_prepare do
  # Helper method for setting ActiveStorage URL options with workspace prefix
  set_active_storage_url_options_method = lambda do |controller|
    controller.class_eval do
      before_action :set_active_storage_url_options, if: -> { Campfire.saas? }

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
  end

  # Apply to ApplicationController (for app controllers)
  set_active_storage_url_options_method.call(ApplicationController)

  # Apply to ActiveStorage controllers so redirect URLs include workspace prefix
  # These don't inherit from ApplicationController, so need separate patching
  if defined?(ActiveStorage::BaseController)
    set_active_storage_url_options_method.call(ActiveStorage::BaseController)
  end
end
