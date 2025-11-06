module Account::Joinable
  extend ActiveSupport::Concern

  included do
    before_create { self.join_code = generate_join_code }
  end

  def reset_join_code
    update! join_code: generate_join_code
  end

  private
    def generate_join_code
      SecureRandom.alphanumeric(12).scan(/.{4}/).join("-")
    end
end
