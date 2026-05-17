module User::DicebearAvatar
  extend ActiveSupport::Concern

  OPEN_TIMEOUT = 3.seconds
  READ_TIMEOUT = 5.seconds
  MAX_AVATAR_SEED = 1_000_000

  included do
    before_create :set_random_avatar_seed, unless: -> { avatar_seed.present? }
  end

  BOT_STYLE = "bottts"

  def dicebear_url
    "#{Dicebear.host}/9.x/#{dicebear_style}/svg?seed=#{avatar_seed || id}"
  end

  def dicebear_svg
    return unless Dicebear.enabled?

    Rails.cache.fetch(dicebear_cache_key, expires_in: 1.week) do
      fetch_dicebear_svg
    end
  end

  def shuffle_avatar_seed!
    Rails.cache.delete(dicebear_cache_key)
    update!(avatar_seed: SecureRandom.random_number(MAX_AVATAR_SEED))
  end

  private

  def dicebear_style
    bot? ? BOT_STYLE : Dicebear.style
  end

  def dicebear_cache_key
    "dicebear/#{dicebear_style}/#{avatar_seed || id}"
  end

  def set_random_avatar_seed
    self.avatar_seed = SecureRandom.random_number(MAX_AVATAR_SEED)
  end

  def fetch_dicebear_svg
    uri = URI(dicebear_url)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    response = http.request(Net::HTTP::Get.new(uri))
    response.body if response.is_a?(Net::HTTPSuccess)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
    Rails.logger.warn("DiceBear API unavailable: #{e.class.name}")
    nil
  end
end
