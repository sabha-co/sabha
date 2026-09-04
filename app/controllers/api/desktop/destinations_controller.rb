class API::Desktop::DestinationsController < API::Desktop::BaseController
  before_action :require_desktop_catalog_authentication

  def show
    render json: Desktop::DestinationCatalog.new(request: request).as_json
  end

  private
    def require_desktop_catalog_authentication
      require_authentication
      return if performed?

      head :unauthorized unless signed_in_for_desktop_api?
    end
end
