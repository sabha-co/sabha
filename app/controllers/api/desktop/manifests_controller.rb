class API::Desktop::ManifestsController < API::Desktop::BaseController
  allow_unauthenticated_access

  def show
    render json: Desktop::ClientManifest.new(request: request).as_json
  end
end
