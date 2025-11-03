class Webhooks::Gumroad::UsersController < Webhooks::Gumroad::BaseController
  before_action :ignore_unrelated_actions

  def create
    event = WebhookEvent.create!(
      source: "gumroad",
      event_type: "sale",
      payload: params.to_unsafe_h
    )

    Gumroad::ImportUserJob.perform_later(event)

    render json: { status: "success" }, status: :ok
  rescue StandardError => e
    Rails.logger.error("ERROR: Failed to process Gumroad sale webhook: #{e.message}")
    render json: { status: "error", message: e.message }, status: :internal_server_error
  end

  private

  def ignore_unrelated_actions
    if params["action"] != "create"
      Rails.logger.info("Ignored sale webhook for an unrelated action: #{params["action"]}")
      render(json: { status: "ignored" }, status: :ok)
    end
  end
end
