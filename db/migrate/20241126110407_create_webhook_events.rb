class CreateWebhookEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :webhook_events do |t|
      t.string :source
      t.string :event_type
      t.text :payload
      t.datetime :processed_at

      t.timestamps
    end
  end
end
