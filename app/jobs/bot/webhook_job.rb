class Bot::WebhookJob < ApplicationJob
  # A webhook or its room can be deleted between enqueue and perform; the
  # GlobalID arguments then fail to deserialize. Discard rather than retry —
  # the records aren't coming back — so the queue closes cleanly instead of
  # recording a failed execution nothing can act on.
  discard_on ActiveJob::DeserializationError::RecordNotFound

  # Retry transient network failures (connection drops, DNS hiccups, SSL
  # renegotiation) and HTTP-level delivery failures (a bot endpoint returning
  # a transient 5xx). Programming errors — NoMethodError, TypeError, nil bugs
  # in the delivery path — are deliberately NOT retried: they surface loudly
  # on the first attempt instead of being silently retried for ~20 minutes
  # before being dropped, which is what `retry_on Exception` did.
  retry_on Net::OpenTimeout, Net::ReadTimeout, Net::HTTPBadResponse,
           Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
           SocketError, EOFError, OpenSSL::SSL::SSLError,
           Webhook::DeliveryError,
           wait: :polynomially_longer, attempts: 10

  def perform(webhook, event_name, payload, room, reply = false)
    return if DemoMode.enabled?

    webhook.deliver(event_name, payload, room, reply: reply)
  end
end
