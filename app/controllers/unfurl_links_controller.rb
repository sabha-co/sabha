class UnfurlLinksController < ApplicationController
  def create
    opengraph = Opengraph::Metadata.from_url(url_param)

    if opengraph.valid?
      render json: opengraph
    else
      head :no_content
    end
  end

  private
    def url_param
      params.require(:url)
    end
end
