class Bot::WebhookJob < ApplicationJob
  retry_on Exception, wait: :polynomially_longer, attempts: 10

  def perform(webhook, payload, room)
    return if DemoMode.enabled?

    webhook.deliver(payload, room)
  end
end
