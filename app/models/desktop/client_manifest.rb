module Desktop
  class ClientManifest
    PROTOCOL_MAJOR = 1

    def initialize(request:)
      @request = request
    end

    def as_json
      {
        protocol_major: PROTOCOL_MAJOR,
        product: product_identity,
        sign_in_path: sign_in_path
      }
    end

    def self.unsupported(requested_major)
      {
        error: "unsupported_protocol_major",
        requested_major: requested_major,
        supported_major: PROTOCOL_MAJOR,
        upgrade_url: "https://github.com/sabha-co/sabha-desktop/releases"
      }
    end

    private
      attr_reader :request

      def product_identity
        {
          name: Branding.app_name,
          short_name: Branding.app_short_name
        }
      end

      def sign_in_path
        if Sabha.saas?
          "/session/new"
        elsif Account.sso_auth? || FirstRun.should_auto_bootstrap?
          "/session/sso"
        else
          "/session/new"
        end
      end
  end
end
