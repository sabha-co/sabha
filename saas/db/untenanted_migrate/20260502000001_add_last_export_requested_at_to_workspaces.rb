class AddLastExportRequestedAtToWorkspaces < ActiveRecord::Migration[8.2]
  def change
    add_column :workspaces, :last_export_requested_at, :datetime
  end
end
