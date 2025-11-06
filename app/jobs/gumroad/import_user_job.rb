class Gumroad::ImportUserJob < ApplicationJob
  def perform(event)
    payload = event.payload || {}

    return if payload["test"] == "true"

    # This will be either:
    # - the buyer's email in case of a normal purchase
    # - the gift receiver email in case of a gift purchase
    # Either way, that's the email we should create the user with.
    email = payload["email"]
    order_id = payload["order_number"]
    membership_started_at = payload["sale_timestamp"]
    if_gift_purchase = payload["is_gift_receiver_purchase"] == "true"
    name = if_gift_purchase ? payload["full_name"] : nil

    raise "Expected email to be present. Event ID #{event.id}" unless email.present?
    raise "Expected order ID to be present. Event ID #{event.id}" unless order_id.present?

    ActiveRecord::Base.transaction do
      begin
        User.create!(email_address: email, name:, order_id:, membership_started_at:)
      rescue ActiveRecord::RecordNotUnique
        if (user = User.find_by(email_address: email))
          user.update!(order_id:, membership_started_at: user.membership_started_at || membership_started_at, suspended_at: nil)
        end
      end
      event.update!(processed_at: Time.current)
    end
  end
end
