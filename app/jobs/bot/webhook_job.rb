class Bot::WebhookJob < ApplicationJob
  retry_on Exception, wait: :polynomially_longer, attempts: 10

  def perform(webhook, event_name, payload, room, reply = false)
    return if DemoMode.enabled?

    webhook.deliver(event_name, payload, room, reply: reply)
  end
end
