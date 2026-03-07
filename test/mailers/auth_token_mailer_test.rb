require "test_helper"

class AuthTokenMailerTest < ActionMailer::TestCase
  test "otp sends multipart email with text and html" do
    user = users(:david)
    auth_token = AuthToken.create!(user: user, expires_at: 15.minutes.from_now)
    email = AuthTokenMailer.otp(auth_token)

    assert_equal 2, email.parts.size
    assert email.parts.any? { |p| p.content_type.include?("text/plain") }
    assert email.parts.any? { |p| p.content_type.include?("text/html") }
  end
end
