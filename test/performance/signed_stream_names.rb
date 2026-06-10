require "active_support/all"
require "json"
require "openssl"
require "base64"

# Regenerates the signed Turbo::StreamsChannel names baked into chatter.js.
#
# These must match what the running app broadcasts to, which depends on two
# things that drifted once already (the GlobalID app name flipped from
# "campfire" to "sabha" during the fork):
#
#   * SECRET_KEY_BASE — the load test boots the perf env with "dummy"
#   * the GlobalID app name — derived from the app module (Sabha => "sabha")
#
# Run with the same values the perf server uses, then paste the output into
# chatter.js:
#
#   ruby signed_stream_names.rb
#   SECRET_KEY_BASE=dummy GID_APP=sabha ruby signed_stream_names.rb
#
# Mirrors Turbo::StreamsChannel signing (turbo-rails): the verifier key is
# derived via Rails' key generator and the name is JSON-serialized + signed.

secret = ENV.fetch("SECRET_KEY_BASE", "dummy")
gid_app = ENV.fetch("GID_APP", "sabha")

key = ActiveSupport::KeyGenerator
  .new(secret, iterations: 1000, hash_digest_class: OpenSSL::Digest::SHA256)
  .generate_key("turbo/signed_stream_verifier_key")
verifier = ActiveSupport::MessageVerifier.new(key, digest: "SHA256", serializer: JSON)

# `to_gid_param` base64-encodes the GlobalID; streamables are joined with ":".
gid_param = ->(model, id) { Base64.urlsafe_encode64("gid://#{gid_app}/#{model}/#{id}", padding: false) }
stream    = ->(*parts) { verifier.generate(parts.join(":")) }

# Streams a member on room 1's page subscribes to. The second one — room 1's
# `messages` stream — is where Message#broadcast_create appends, so it's the one
# that actually exercises message fan-out.
puts stream.call("rooms")
puts stream.call(gid_param.call("Rooms::Closed", 1), "messages")
puts stream.call(gid_param.call("User", 1), "rooms")
