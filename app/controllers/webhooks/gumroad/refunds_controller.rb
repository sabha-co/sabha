class Webhooks::Gumroad::RefundsController < Webhooks::Gumroad::BaseController
  def create
    event = WebhookEvent.create!(
      source: "gumroad",
      event_type: "refund",
      payload: params.to_unsafe_h
    )

    Gumroad::ProcessRefundJob.perform_later(event)

    render json: { status: "success" }, status: :ok
  rescue StandardError => e
    Rails.logger.error("ERROR: Failed to process Gumroad refund webhook: #{e.message}")
    render json: { status: "error", message: e.message }, status: :internal_server_error
  end
end
