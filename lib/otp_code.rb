# frozen_string_literal: true

# Shared OTP code generation and validation
#
# Used by:
# - AuthToken (self-hosted OTP login)
# - AuthCode (SaaS passwordless authentication)
#
# Features:
# - Alphanumeric codes (more entropy than numeric-only)
# - Excludes ambiguous characters (O, I, L) for readability
# - Auto-corrects common typos (O→0, I→1, L→1)
# - Strips spaces and dashes from user input

module OtpCode
  # Alphabet excluding ambiguous characters (O, I, L)
  # Makes codes easier to read and type correctly
  ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".chars.freeze

  # Common typo substitutions
  SUBSTITUTIONS = {
    "O" => "0",
    "I" => "1",
    "L" => "1"
  }.freeze

  class << self
    # Generate a random code of given length
    # Default length of 6 provides ~30 bits of entropy
    def generate(length = 6)
      length.times.map { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join
    end

    # Sanitize user input:
    # - Uppercase
    # - Auto-correct common typos (O→0, I→1, L→1)
    # - Remove invalid characters (spaces, dashes, etc.)
    def sanitize(code)
      code.to_s
          .upcase
          .then { |c| substitute_typos(c) }
          .then { |c| remove_invalid_chars(c) }
    end

    private

      def substitute_typos(code)
        SUBSTITUTIONS.reduce(code) do |result, (from, to)|
          result.gsub(from, to)
        end
      end

      def remove_invalid_chars(code)
        code.gsub(/[^#{ALPHABET.join}]/, "")
      end
  end
end
