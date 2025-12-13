require "test_helper"

class ChangePasswordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:david)
    # Use the standard test password that sign_in helper expects
    @user.update!(password: "secret123456", must_change_password: false)
  end

  test "show redirects to root when user does not need password change" do
    sign_in @user

    get change_password_path
    assert_redirected_to root_path
  end

  test "show renders form when user must change password" do
    @user.update!(must_change_password: true)
    sign_in @user

    get change_password_path
    assert_response :success
    assert_select "form"
    assert_select "input[name='password']"
    assert_select "input[name='password_confirmation']"
  end

  test "update redirects to root when user does not need password change" do
    sign_in @user

    patch change_password_path, params: {
      password: "newpassword123",
      password_confirmation: "newpassword123"
    }
    assert_redirected_to root_path
  end

  test "update changes password and clears must_change_password flag" do
    @user.update!(must_change_password: true)
    sign_in @user

    patch change_password_path, params: {
      password: "newpassword123",
      password_confirmation: "newpassword123"
    }

    assert_redirected_to root_path
    @user.reload
    assert_not @user.must_change_password?
    assert @user.authenticate("newpassword123")
  end

  test "update fails when password is blank" do
    @user.update!(must_change_password: true)
    sign_in @user

    patch change_password_path, params: {
      password: "",
      password_confirmation: ""
    }

    assert_response :unprocessable_entity
    assert_select ".txt-negative", text: /Password can't be blank/
  end

  test "update fails when password is too short" do
    @user.update!(must_change_password: true)
    sign_in @user

    patch change_password_path, params: {
      password: "short",
      password_confirmation: "short"
    }

    assert_response :unprocessable_entity
    assert_select ".txt-negative", text: /Password is too short/
  end

  test "update fails when password confirmation does not match" do
    @user.update!(must_change_password: true)
    sign_in @user

    patch change_password_path, params: {
      password: "newpassword123",
      password_confirmation: "differentpassword"
    }

    assert_response :unprocessable_entity
    assert_select ".txt-negative", text: /Password confirmation doesn't match/
  end

  test "update fails when new password matches temporary password" do
    @user.update!(must_change_password: true)
    sign_in @user

    ENV["ADMIN_PASSWORD"] = "temporary-password"

    patch change_password_path, params: {
      password: "temporary-password",
      password_confirmation: "temporary-password"
    }

    assert_response :unprocessable_entity
    assert_select ".txt-negative", text: /Please choose a different password/
  ensure
    ENV.delete("ADMIN_PASSWORD")
  end
end
