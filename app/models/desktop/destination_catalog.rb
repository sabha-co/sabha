module Desktop
  class DestinationCatalog
    def initialize(request:)
      @request = request
    end

    def as_json
      {
        protocol_major: ClientManifest::PROTOCOL_MAJOR,
        destinations: destinations
      }
    end

    private
      attr_reader :request

      def destinations
        if Sabha.saas?
          Saas.new(request: request).destinations
        else
          [ self_hosted_destination ]
        end
      end

      def self_hosted_destination
        account = Current.account
        {
          id: "default",
          name: account.name,
          logo_url: account_logo_url,
          base_path: "/",
          cable_path: "/api/cable"
        }
      end

      def account_logo_url
        return unless Current.account&.logo&.attached?

        Rails.application.routes.url_helpers.account_logo_url(
          size: "small",
          host: request.host,
          protocol: request.protocol
        )
      end
  end
end
