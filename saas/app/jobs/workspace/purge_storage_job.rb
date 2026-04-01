# frozen_string_literal: true

class Workspace
  class PurgeStorageJob < ApplicationJob
    queue_as :default

    def perform(tenant_id)
      ApplicationRecord.with_tenant(tenant_id) do
        ActiveStorage::Blob.find_each(&:purge)
      end
      ApplicationRecord.destroy_tenant(tenant_id)
    end
  end
end
