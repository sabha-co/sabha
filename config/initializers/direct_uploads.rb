module ActiveStorageDirectUploadsControllerAuthentication
  extend ActiveSupport::Concern

  included do
    include Authentication
    skip_before_action :deny_bots  # Bots don't upload files

    private
      # Override Authentication's redirect — this is a JSON API endpoint
      def request_authentication
        head :unauthorized
      end
  end
end

Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.include ActiveStorageDirectUploadsControllerAuthentication
end
