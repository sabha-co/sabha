# frozen_string_literal: true

class AddWorkspaceMembershipIdToUsers < ActiveRecord::Migration[8.0]
  def change
    # workspace_membership_id links User to GlobalIdentity via WorkspaceMembership
    # This column is only used in SaaS mode; in single-tenant mode it remains NULL
    #
    # Note: No foreign key constraint because WorkspaceMembership is in a different database
    add_column :users, :workspace_membership_id, :bigint
    add_index :users, :workspace_membership_id
  end
end
