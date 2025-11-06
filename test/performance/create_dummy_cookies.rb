key_generator = ActiveSupport::KeyGenerator.new("dummy", iterations: 1000)
signed_cookie_secret = key_generator.generate_key("signed cookie")
signed_cookie_verifier = ActiveSupport::MessageVerifier.new(signed_cookie_secret, digest: "SHA1", serializer: ActiveSupport::MessageEncryptor::NullSerializer)

(1..10000).each do |id|
  token = "a" * 19 + id.to_s.rjust(5, "0")
  puts signed_cookie_verifier.generate("\"#{token}\"", expires_in: 20.years, purpose: "cookie.session_token")
end
