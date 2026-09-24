# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class API::ManifestsSaasControllerTest < ActionDispatch::IntegrationTest
    test "describes the product but no single community" do
      get "/api/manifest", headers: { "Sabha-Protocol-Major" => "1" }

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "Sabha", body.dig("product", "name")
      refute body.key?("community")
      assert body["multi_tenant"]
    end
  end
end
