# frozen_string_literal: true

class AddConsentedAtToRemoteWorkspaceMemberships < ActiveRecord::Migration[8.2]
  def change
    add_column :remote_workspace_memberships, :consented_at, :datetime
  end
end
