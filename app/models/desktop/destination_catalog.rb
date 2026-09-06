module Desktop
  class DestinationCatalog
    def initialize(request:)
      @request = request
    end

    def as_json
      {
        protocol_major: ClientManifest::PROTOCOL_MAJOR,
        peers: peers
      }
    end

    private
      attr_reader :request

      def peers
        if Sabha.saas?
          Saas.new(request: request).peers
        else
          [ self_hosted_peer ]
        end
      end

      def self_hosted_peer
        account = Current.account
        {
          id: "default",
          name: account.name,
          logo_url: account_logo_url,
          workspace_url: "#{request.base_url}/",
          cable_url: "#{request.base_url}/api/cable"
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
