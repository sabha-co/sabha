class AddWebhookSecretToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :webhook_secret, :string
  end
end
