module ActiveStorageDirectUploadsControllerAuthentication
  extend ActiveSupport::Concern

  included do
    include Authentication
    skip_before_action :deny_bots  # Bots don't upload files
    before_action :check_storage_limit

    private
      # Override Authentication's redirect — this is a JSON API endpoint
      def request_authentication
        head :unauthorized
      end

      def check_storage_limit
        if Sabha.saas? && Current.account&.exceeding_storage_limit?
          head :unprocessable_entity
        end
      end
  end
end

Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.include ActiveStorageDirectUploadsControllerAuthentication
end
