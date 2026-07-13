# Cable config discovery: hands a signed-in client its WebSocket URL and a
# freshly-minted JWT identity so it can connect (and refresh on token_expired)
# without scraping the HTML meta tag. Exposes only socket credentials — no
# message content — so a non-browser client inherits the same identity/transport
# contract the web client gets from `action-cable-url`.
class API::CablesController < ApplicationController
  def show
    render json: {
      url: cable_url,
      token: AnyCable::JWT.encode(cable_identifiers),
      expires_in: AnyCable.config.jwt_ttl
    }
  end

  private
    def cable_identifiers
      identifiers = { current_user: Current.user }
      identifiers[:current_tenant] = ApplicationRecord.current_tenant.to_s if Sabha.saas?
      identifiers
    end

    def cable_url
      if Sabha.saas?
        base = ActionCable.server.config.url || "#{request.script_name}/cable"
        "#{base}?wid=#{ApplicationRecord.current_tenant}"
      else
        ActionCable.server.config.url || ActionCable.server.config.mount_path
      end
    end

    # A JSON client gets a 401, not the HTML login redirect.
    def request_authentication
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
end
