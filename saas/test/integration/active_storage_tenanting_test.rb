# frozen_string_literal: true

require_relative "../test_helper"

class ActiveStorageTenantingTest < ActiveSupport::TestCase
  # Tests that ActiveStorage blob keys and disk paths are tenant-scoped
  # The activerecord-tenanted gem:
  # 1. Prepends tenant to blob keys: "1000001/abc123token"
  # 2. Stores files in tenant subfolder: storage/1000001/ab/c1/abc123...

  setup do
    @workspace = workspaces(:acme)
    @tenant_id = @workspace.external_id.to_s

    # Ensure tenant database exists
    ApplicationRecord.create_tenant(@tenant_id) unless ApplicationRecord.tenant_exist?(@tenant_id)
  end

  test "blob keys are unique per tenant" do
    workspace_b = workspaces(:widgets)
    tenant_b = workspace_b.external_id.to_s

    # Ensure both tenant databases exist
    ApplicationRecord.create_tenant(tenant_b) unless ApplicationRecord.tenant_exist?(tenant_b)

    key_a = nil
    key_b = nil

    ApplicationRecord.with_tenant(@tenant_id) do
      blob_a = ActiveStorage::Blob.create_before_direct_upload!(
        filename: "test.txt",
        byte_size: 100,
        checksum: "abc123",
        content_type: "text/plain"
      )
      key_a = blob_a.key
    end

    ApplicationRecord.with_tenant(tenant_b) do
      blob_b = ActiveStorage::Blob.create_before_direct_upload!(
        filename: "test.txt",
        byte_size: 100,
        checksum: "abc123",
        content_type: "text/plain"
      )
      key_b = blob_b.key
    end

    # Keys should have different tenant prefixes
    assert key_a.start_with?("#{@tenant_id}/")
    assert key_b.start_with?("#{tenant_b}/")
    assert_not_equal key_a, key_b
  end
end
