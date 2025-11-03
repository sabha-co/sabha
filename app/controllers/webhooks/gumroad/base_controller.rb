class Webhooks::Gumroad::BaseController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection

  before_action :verify_webhook_secret
  before_action :ignore_unrelated_products

  protected

  def verify_webhook_secret
    unless params[:webhook_secret] == ENV["WEBHOOK_SECRET"]
      Rails.logger.warn("ERROR: Unauthorized webhook attempt #{params.inspect}")
      render json: { status: "error", message: "Unauthorized" }, status: :unauthorized
    end
  end

  def ignore_unrelated_products
    unless GumroadAPI.product_ids.include?(params["product_id"].to_s)
      Rails.logger.info("Ignored webhook for unrelated product_id: #{params["product_id"]}")
      render(json: { status: "ignored" }, status: :ok)
    end
  end
end
