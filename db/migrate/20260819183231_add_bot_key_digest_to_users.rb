require "digest"

class AddBotKeyDigestToUsers < ActiveRecord::Migration[8.2]
  # Bot bearer keys move from a derivable "<id>-<token>" credential to a
  # shown-once "sabha_bot_<hex>" key stored only as a SHA-256 digest. Existing
  # bots keep authenticating unchanged: we backfill the digest of their current
  # derivable key, so the key they already hold still hashes to a match.
  def up
    # Guarded so a tenant DB that already carries the column (created from a
    # newer schema, or drifted) doesn't abort the whole fleet migrate.
    add_column :users, :bot_key_digest, :string unless column_exists?(:users, :bot_key_digest)
    add_column :users, :bot_key_rotated_at, :datetime unless column_exists?(:users, :bot_key_rotated_at)
    add_index :users, :bot_key_digest, unique: true unless index_exists?(:users, :bot_key_digest)

    # bot_token is set only on bots, so its presence identifies them without
    # coupling this migration to the role enum.
    users = Class.new(ActiveRecord::Base) { self.table_name = "users" }
    users.reset_column_information
    users.where.not(bot_token: nil).find_each do |bot|
      bot.update_columns(
        bot_key_digest: Digest::SHA256.hexdigest("#{bot.id}-#{bot.bot_token}"),
        bot_key_rotated_at: bot.created_at
      )
    end
  end

  def down
    remove_index :users, :bot_key_digest
    remove_column :users, :bot_key_rotated_at
    remove_column :users, :bot_key_digest
  end
end
