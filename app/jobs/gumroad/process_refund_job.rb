class Gumroad::ProcessRefundJob < ApplicationJob
  def perform(event)
    payload = event.payload || {}
    order_id = payload["order_number"]
    fully_refunded = payload["refunded"] == "true" || payload["disputed"] == "true"

    raise "Expected order ID to be present. Event ID #{event.id}" unless order_id.present?

    ActiveRecord::Base.transaction do
      User.find_by(order_id:)&.suspend! if fully_refunded
      event.update!(processed_at: Time.current)
    end
  end
end
