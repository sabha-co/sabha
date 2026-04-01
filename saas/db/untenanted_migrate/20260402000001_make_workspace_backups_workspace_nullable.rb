class MakeWorkspaceBackupsWorkspaceNullable < ActiveRecord::Migration[8.0]
  def change
    remove_foreign_key :workspace_backups, :workspaces
    change_column_null :workspace_backups, :workspace_id, true
  end
end
