# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class LandingControllerTest < ActionDispatch::IntegrationTest
    test "show renders landing page for unauthenticated users" do
      get root_path
      assert_response :success
    end

    test "show redirects authenticated users to most recent workspace" do
      sign_in_global_identity(global_identities(:alice))
      get root_path
      # Redirects directly to most recently accessed workspace
      assert_response :redirect
    end
  end
end
