# frozen_string_literal: true

require_relative "../test_helper"

class ActiveStorageAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:acme)
    @tenant_id = @workspace.external_id.to_s

    ApplicationRecord.create_tenant(@tenant_id) unless ApplicationRecord.tenant_exist?(@tenant_id)
  end

  test "unauthenticated blob access returns unauthorized" do
    blob = create_blob_in_workspace

    get "/#{@workspace.external_id}/rails/active_storage/blobs/proxy/#{blob.signed_id}/#{blob.filename}"

    assert_response :unauthorized
  end

  test "authenticated workspace member can access blob" do
    blob = create_blob_in_workspace
    sign_in_global_identity(global_identities(:alice))

    get "/#{@workspace.external_id}/rails/active_storage/blobs/proxy/#{blob.signed_id}/#{blob.filename}"

    assert_response :success
  end

  test "authenticated non-member is blocked from accessing workspace blob" do
    blob = create_blob_in_workspace

    # Bob is NOT a member of acme
    sign_in_global_identity(global_identities(:bob))

    get "/#{@workspace.external_id}/rails/active_storage/blobs/proxy/#{blob.signed_id}/#{blob.filename}"

    assert_redirected_to "/workspaces"
  end

  test "unauthenticated direct upload returns unauthorized" do
    post "/#{@workspace.external_id}/rails/active_storage/direct_uploads", params: {
      blob: { filename: "test.png", byte_size: 123, checksum: "abc", content_type: "image/png" }
    }, as: :json

    assert_response :unauthorized
  end

  test "authenticated non-member is blocked from direct upload" do
    # Bob is NOT a member of acme
    sign_in_global_identity(global_identities(:bob))

    post "/#{@workspace.external_id}/rails/active_storage/direct_uploads", params: {
      blob: { filename: "test.png", byte_size: 123, checksum: "abc", content_type: "image/png" }
    }, as: :json

    assert_redirected_to "/workspaces"
  end

  test "direct upload round-trips through the workspace-prefixed disk URL" do
    sign_in_global_identity(global_identities(:alice))
    data = "fake-png-bytes"
    checksum = OpenSSL::Digest::MD5.base64digest(data)

    post "/#{@workspace.external_id}/rails/active_storage/direct_uploads", params: {
      blob: { filename: "test.png", byte_size: data.bytesize, checksum: checksum, content_type: "image/png" }
    }, as: :json
    assert_response :success

    upload_url = response.parsed_body.dig("direct_upload", "url")
    assert_includes upload_url, "/#{@workspace.external_id}/rails/active_storage/disk/",
      "direct-upload URL is missing the workspace prefix; the browser's PUT would hit the tenant-less apex path"

    # The browser PUTs the bytes to that URL. Without the prefix it lands on the
    # tenant-less apex path and DiskService raises NoTenantError (HTTP 500); with
    # the prefix the tenant resolves and the upload succeeds.
    put URI.parse(upload_url).request_uri, params: data, headers: { "Content-Type" => "image/png" }
    assert_response :no_content
  end

  private
    def create_blob_in_workspace
      ApplicationRecord.with_tenant(@tenant_id) do
        ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("hello"), filename: "test.txt", content_type: "text/plain"
        )
      end
    end
end
