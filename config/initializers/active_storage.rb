require_relative "../../lib/rails_ext/active_storage_analyze_job_suppress_broadcasts"
require_relative "../../lib/rails_ext/active_storage_direct_upload_expiry"

ActiveSupport.on_load(:active_storage_blob) do
  ActiveStorage::DiskController.after_action only: :show do
    expires_in 5.minutes, public: true
  end
end

# Require authentication on all blob-serving controllers.
# Sabha is a private chat app — all content requires login.
# Avatars bypass this (served via Users::AvatarsController, not Active Storage controllers).
module ActiveStorageBlobControllerAuthentication
  extend ActiveSupport::Concern

  included do
    include Authentication
    skip_before_action :deny_bots

    # Re-order: authenticate AFTER set_blob (which is already registered)
    skip_before_action :require_authentication
    before_action :require_authentication

    private
      # Override Authentication's redirect — these endpoints serve files, not HTML
      def request_authentication
        head :unauthorized
      end
  end
end

Rails.application.config.to_prepare do
  [
    ActiveStorage::Blobs::RedirectController,
    ActiveStorage::Blobs::ProxyController,
    ActiveStorage::Representations::RedirectController,
    ActiveStorage::Representations::ProxyController
  ].each do |controller|
    controller.include ActiveStorageBlobControllerAuthentication
  end
end
