require "test_helper"

class Users::AvatarsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    # Re-enable WebMock (system tests call WebMock.disable!)
    WebMock.enable!
    WebMock.reset!
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  teardown do
    WebMock.reset!
  end

  test "show initials when dicebear disabled" do
    Rails.configuration.x.dicebear.enabled = false
    get user_avatar_url(users(:kevin).avatar_token)
    assert_select "text", text: "K"
  ensure
    Rails.configuration.x.dicebear.enabled = true
  end

  test "show dicebear avatar when enabled" do
    svg_content = '<svg xmlns="http://www.w3.org/2000/svg"><circle/></svg>'
    stub_request(:get, %r{api\.dicebear\.com}).to_return(
      status: 200,
      body: svg_content,
      headers: { "Content-Type" => "image/svg+xml" }
    )

    get user_avatar_url(users(:kevin).avatar_token)

    assert_response :success
    assert_equal "image/svg+xml", response.content_type
    assert_equal svg_content, response.body
  end

  test "show initials when dicebear API fails" do
    # Use unique seed to avoid cache interference
    users(:kevin).update!(avatar_seed: SecureRandom.random_number(1_000_000))

    stub_request(:get, %r{api\.dicebear\.com}).to_return(status: 500)

    get user_avatar_url(users(:kevin).avatar_token)

    assert_response :success
    assert_select "text", text: "K"
  end

  test "show the uploaded avatar resized to a square webp" do
    users(:kevin).avatar.attach io: file_fixture("moon.jpg").open, filename: "moon.jpg", content_type: "image/jpeg"

    get user_avatar_url(users(:kevin).avatar_token)

    assert_response :success
    assert_equal "image/webp", response.content_type

    image = Vips::Image.new_from_buffer response.body, ""
    assert_equal [ 512, 512 ], [ image.width, image.height ]
  end

  test "show initials when the uploaded avatar cannot be resized" do
    Rails.configuration.x.dicebear.enabled = false
    users(:kevin).avatar.attach io: file_fixture("pixel.bmp").open, filename: "pixel.png", content_type: "image/png"

    get user_avatar_url(users(:kevin).avatar_token)

    assert_response :success
    assert_select "text", text: "K"
  ensure
    Rails.configuration.x.dicebear.enabled = true
  end

  test "show image with invalid token responds 404" do
    get user_avatar_url("not-a-valid-token")

    assert_response :not_found
  end

  test "destroy removes avatar and redirects to profile" do
    user = users(:david)
    user.avatar.attach(
      io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg"></svg>'),
      filename: "test-avatar.svg",
      content_type: "image/svg+xml"
    )
    assert user.avatar.attached?

    delete user_avatar_url(user.avatar_token)

    assert_redirected_to user_profile_url
    assert_not user.reload.avatar.attached?
  end
end
