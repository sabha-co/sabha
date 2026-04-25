require "test_helper"

class Autocompletable::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "search returns matching users" do
    get autocompletable_users_url(format: :json), params: { query: "da" }

    assert_response :success
    assert_equal "David", response.parsed_body.first["name"]
  end

  test "search results escape HTML in names" do
    users(:david).update!(name: "David <script>alert(123)</script>")

    get autocompletable_users_url(format: :json), params: { query: "da" }

    assert_response :success
    assert_equal "David &lt;script&gt;alert(123)&lt;/script&gt;", response.parsed_body.first["name"]
  end

  test "room search returns matching users" do
    get autocompletable_users_url(room_id: rooms(:hq).id, format: :json), params: { query: "da" }

    assert_response :success
    assert_equal "David", response.parsed_body.first["name"]
  end

  test "room search is scoped by membership" do
    sign_in :kevin

    assert_not_includes users(:kevin).rooms, rooms(:watercooler)

    assert_raises ActiveRecord::RecordNotFound do
      get autocompletable_users_url(room_id: rooms(:watercooler).id, format: :json), params: { query: "da" }
    end
  end

  test "blank query returns recent users (mention picker default)" do
    get autocompletable_users_url(format: :json), params: { query: "" }

    assert_response :success
    assert response.parsed_body.is_a?(Array)
    assert response.parsed_body.size > 0, "blank query should populate the @-mention picker"
  end

  test "exact first name matches appear before partial matches" do
    davidson = User.create!(name: "Davidson Smith", email_address: "davidson@example.com", password: "secret123456", verified_at: 1.day.ago)

    get autocompletable_users_url(format: :json), params: { query: "David" }

    assert_response :success
    names = response.parsed_body.map { |u| u["name"] }

    assert_includes names, "David"
    assert_includes names, "Davidson Smith"
    assert names.index("David") < names.index("Davidson Smith"), "Exact first name match 'David' should appear before partial match 'Davidson Smith'"
  end
end
