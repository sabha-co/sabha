class SimplifyAuthentication < ActiveRecord::Migration[8.2]
  def change
    # AUTH_METHOD is now ENV-only, no longer stored in database
    remove_column :accounts, :auth_method, :string

    # Force password change flow removed (was for ADMIN_PASSWORD bootstrap)
    remove_column :users, :must_change_password, :boolean, default: false
  end
end
