# frozen_string_literal: true

require "test_helper"

class AuthCodeMailerTest < ActionMailer::TestCase
  test "code sends multipart email with text and html" do
    auth_code = auth_codes(:alice_signin)
    email = AuthCodeMailer.code(auth_code)

    assert_equal 2, email.parts.size
    assert email.parts.any? { |p| p.content_type.include?("text/plain") }
    assert email.parts.any? { |p| p.content_type.include?("text/html") }
  end

  test "code sends to global identity email for sign-in" do
    auth_code = auth_codes(:alice_signin)
    email = AuthCodeMailer.code(auth_code)

    assert_equal [ "alice@example.com" ], email.to
  end

  test "code sends to unconfirmed email for email change" do
    auth_code = auth_codes(:email_change)
    email = AuthCodeMailer.code(auth_code)

    assert_equal [ "newpending@example.com" ], email.to
  end

  test "code includes the OTP in body" do
    auth_code = auth_codes(:alice_signin)
    email = AuthCodeMailer.code(auth_code)

    assert_match auth_code.code, email.text_part.body.to_s
    assert_match auth_code.code, email.html_part.body.to_s
  end
end
