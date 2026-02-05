# frozen_string_literal: true

require "test_helper"

class OtpCodeTest < ActiveSupport::TestCase
  test "generate creates code of specified length" do
    code = OtpCode.generate(6)
    assert_equal 6, code.length
  end

  test "generate uses only valid alphabet characters" do
    100.times do
      code = OtpCode.generate(6)
      assert code.chars.all? { |c| OtpCode::ALPHABET.include?(c) }
    end
  end

  test "generate excludes ambiguous characters O, I, L" do
    100.times do
      code = OtpCode.generate(10)
      assert_not_includes code, "O"
      assert_not_includes code, "I"
      assert_not_includes code, "L"
    end
  end

  test "sanitize converts to uppercase" do
    assert_equal "ABC123", OtpCode.sanitize("abc123")
  end

  test "sanitize substitutes O with 0" do
    assert_equal "A0B", OtpCode.sanitize("AOB")
    assert_equal "A0B", OtpCode.sanitize("aob")
  end

  test "sanitize substitutes I with 1" do
    assert_equal "A1B", OtpCode.sanitize("AIB")
    assert_equal "A1B", OtpCode.sanitize("aib")
  end

  test "sanitize substitutes L with 1" do
    assert_equal "A1B", OtpCode.sanitize("ALB")
    assert_equal "A1B", OtpCode.sanitize("alb")
  end

  test "sanitize removes spaces and dashes" do
    assert_equal "ABC123", OtpCode.sanitize("ABC 123")
    assert_equal "ABC123", OtpCode.sanitize("ABC-123")
    assert_equal "ABC123", OtpCode.sanitize("A B C - 1 2 3")
  end

  test "sanitize handles nil input" do
    assert_equal "", OtpCode.sanitize(nil)
  end
end
