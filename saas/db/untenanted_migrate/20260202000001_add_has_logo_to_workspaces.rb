# frozen_string_literal: true

class AddHasLogoToWorkspaces < ActiveRecord::Migration[8.0]
  def change
    return unless table_exists?(:workspaces)
    return if column_exists?(:workspaces, :has_logo)

    add_column :workspaces, :has_logo, :boolean, default: false, null: false
  end
end
