require "test_helper"

class User::DicebearAvatarTest < ActiveSupport::TestCase
  setup do
    @user = users(:kevin)
    @original_config = Rails.configuration.x.dicebear.dup
    # Re-enable WebMock (system tests call WebMock.disable!)
    WebMock.enable!
    WebMock.reset!
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  teardown do
    Rails.configuration.x.dicebear.enabled = @original_config.enabled
    Rails.configuration.x.dicebear.host = @original_config.host
    Rails.configuration.x.dicebear.style = @original_config.style
    WebMock.reset!
  end

  # dicebear_url

  test "dicebear_url uses avatar_seed when present" do
    @user.update!(avatar_seed: 12345)
    url = @user.dicebear_url
    assert_match %r{seed=12345$}, url
  end

  test "dicebear_url uses user id when avatar_seed is nil" do
    @user.update_column(:avatar_seed, nil)
    url = @user.dicebear_url
    assert_match %r{seed=#{@user.id}$}, url
  end

  test "dicebear_url uses configured host" do
    Rails.configuration.x.dicebear.host = "https://custom.dicebear.local"
    url = @user.dicebear_url
    assert url.start_with?("https://custom.dicebear.local/")
  end

  test "dicebear_url uses configured style" do
    Rails.configuration.x.dicebear.style = "avataaars"
    url = @user.dicebear_url
    assert_match %r{/9\.x/avataaars/svg}, url
  end

  # shuffle_avatar_seed!

  test "shuffle_avatar_seed! generates new random seed" do
    old_seed = @user.avatar_seed
    @user.shuffle_avatar_seed!
    assert_not_equal old_seed, @user.avatar_seed
  end

  test "shuffle_avatar_seed! clears the cache" do
    Rails.configuration.x.dicebear.enabled = true
    svg_content = '<svg xmlns="http://www.w3.org/2000/svg"><circle/></svg>'

    stub_request(:get, %r{api\.dicebear\.com}).to_return(
      status: 200,
      body: svg_content,
      headers: { "Content-Type" => "image/svg+xml" }
    )

    # Populate cache
    @user.dicebear_svg

    # Shuffle should clear old cache
    old_seed = @user.avatar_seed
    @user.shuffle_avatar_seed!

    # New seed means new cache key, old one should be gone
    old_cache_key = "dicebear/#{Dicebear.style}/#{old_seed}"
    assert_nil Rails.cache.read(old_cache_key)
  end

  # before_create callback

  test "sets random avatar_seed on create" do
    user = User.create!(
      name: "Test User",
      email_address: "test-dicebear-#{SecureRandom.hex(4)}@example.com",
      password: "secret123456"
    )
    assert_not_nil user.avatar_seed
    assert user.avatar_seed.is_a?(Integer)
    assert user.avatar_seed > 0
  end

  # dicebear_svg

  test "dicebear_svg returns nil when dicebear disabled" do
    Rails.configuration.x.dicebear.enabled = false
    assert_nil @user.dicebear_svg
  end

  test "dicebear_svg fetches and returns SVG content" do
    Rails.configuration.x.dicebear.enabled = true
    svg_content = '<svg xmlns="http://www.w3.org/2000/svg"><circle/></svg>'

    stub_request(:get, %r{api\.dicebear\.com}).to_return(
      status: 200,
      body: svg_content,
      headers: { "Content-Type" => "image/svg+xml" }
    )

    result = @user.dicebear_svg

    assert_equal svg_content, result
  end

  test "dicebear_svg returns nil on API failure" do
    Rails.configuration.x.dicebear.enabled = true
    # Use unique seed to avoid cache interference
    @user.update!(avatar_seed: SecureRandom.random_number(1_000_000))

    stub_request(:get, %r{api\.dicebear\.com}).to_return(status: 500)

    assert_nil @user.dicebear_svg
  end

  test "dicebear_svg returns nil on network timeout" do
    Rails.configuration.x.dicebear.enabled = true
    # Use unique seed to avoid cache interference
    @user.update!(avatar_seed: SecureRandom.random_number(1_000_000))

    stub_request(:get, %r{api\.dicebear\.com}).to_timeout

    assert_nil @user.dicebear_svg
  end

  test "dicebear_svg returns nil on connection refused" do
    Rails.configuration.x.dicebear.enabled = true
    # Use unique seed to avoid cache interference
    @user.update!(avatar_seed: SecureRandom.random_number(1_000_000))

    stub_request(:get, %r{api\.dicebear\.com}).to_raise(Errno::ECONNREFUSED)

    assert_nil @user.dicebear_svg
  end
end
