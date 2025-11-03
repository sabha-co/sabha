class AddReceivesToWebhooks < ActiveRecord::Migration[7.2]
  def up
    add_column :webhooks, :receives, :string
    execute("update webhooks set receives='mentions'")
  end

  def down
    remove_column :webhooks, :receives
  end
end
