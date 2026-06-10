require "active_support/all"

# Mirrors how Rails derives and verifies the signed `session_token` cookie, so the
# load test can authenticate as the users seeded by config/environments/performance.rb.
# All of these track Rails defaults (load_defaults 8.2): the "signed cookie" salt, a
# SHA256-derived key generator, a SHA1 message verifier, and the JSON-serialized,
# purpose-scoped cookie. The token is JSON-encoded by hand (quotes) and signed with
# the NullSerializer so the bytes match what the :json cookie serializer produces.
secret = ENV.fetch("SECRET_KEY_BASE", "dummy")
key_generator = ActiveSupport::KeyGenerator.new(secret, iterations: 1000, hash_digest_class: OpenSSL::Digest::SHA256)
signed_cookie_secret = key_generator.generate_key("signed cookie")
signed_cookie_verifier = ActiveSupport::MessageVerifier.new(signed_cookie_secret, digest: "SHA1", serializer: ActiveSupport::MessageEncryptor::NullSerializer)

(1..10000).each do |id|
  token = "a" * 19 + id.to_s.rjust(5, "0")
  puts signed_cookie_verifier.generate("\"#{token}\"", expires_in: 20.years, purpose: "cookie.session_token")
end
