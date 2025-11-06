class WebhookEvent < ApplicationRecord
  serialize :payload, coder: JSON

  after_create :trim_old_events

  private

  def trim_old_events
    WebhookEvent.where(created_at: ..3.months.ago).delete_all
  end
end
