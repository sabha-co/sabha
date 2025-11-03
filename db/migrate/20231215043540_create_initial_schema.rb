class CreateInitialSchema < ActiveRecord::Migration[7.2]
  def change
    create_table "accounts", force: :cascade do |t|
      t.string "name", null: false
      t.string "join_code", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end

    create_table "action_text_rich_texts", force: :cascade do |t|
      t.string "name", null: false
      t.text "body"
      t.string "record_type", null: false
      t.bigint "record_id", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index [ "record_type", "record_id", "name" ], name: "index_action_text_rich_texts_uniqueness", unique: true
    end

    create_table "active_storage_attachments", force: :cascade do |t|
      t.string "name", null: false
      t.string "record_type", null: false
      t.bigint "record_id", null: false
      t.bigint "blob_id", null: false
      t.datetime "created_at", null: false
      t.index [ "blob_id" ], name: "index_active_storage_attachments_on_blob_id"
      t.index [ "record_type", "record_id", "name", "blob_id" ], name: "index_active_storage_attachments_uniqueness", unique: true
    end

    create_table "active_storage_blobs", force: :cascade do |t|
      t.string "key", null: false
      t.string "filename", null: false
      t.string "content_type"
      t.text "metadata"
      t.string "service_name", null: false
      t.bigint "byte_size", null: false
      t.string "checksum"
      t.datetime "created_at", null: false
      t.index [ "key" ], name: "index_active_storage_blobs_on_key", unique: true
    end

    create_table "active_storage_variant_records", force: :cascade do |t|
      t.bigint "blob_id", null: false
      t.string "variation_digest", null: false
      t.index [ "blob_id", "variation_digest" ], name: "index_active_storage_variant_records_uniqueness", unique: true
    end

    create_table "boosts", force: :cascade do |t|
      t.integer "message_id", null: false
      t.integer "booster_id", null: false
      t.string "content", limit: 16, null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index [ "booster_id" ], name: "index_boosts_on_booster_id"
      t.index [ "message_id" ], name: "index_boosts_on_message_id"
    end

    create_table "memberships", force: :cascade do |t|
      t.integer "room_id", null: false
      t.integer "user_id", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.datetime "unread_at"
      t.string "involvement", default: "mentions"
      t.integer "connections", default: 0, null: false
      t.datetime "connected_at"
      t.index [ "room_id", "created_at" ], name: "index_memberships_on_room_id_and_created_at"
      t.index [ "room_id", "user_id" ], name: "index_memberships_on_room_id_and_user_id", unique: true
      t.index [ "room_id" ], name: "index_memberships_on_room_id"
      t.index [ "user_id" ], name: "index_memberships_on_user_id"
    end

    create_table "messages", force: :cascade do |t|
      t.integer "room_id", null: false
      t.integer "creator_id", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.string "client_message_id", null: false
      t.index [ "creator_id" ], name: "index_messages_on_creator_id"
      t.index [ "room_id" ], name: "index_messages_on_room_id"
    end

    create_table "push_subscriptions", force: :cascade do |t|
      t.integer "user_id", null: false
      t.string "endpoint"
      t.string "p256dh_key"
      t.string "auth_key"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.string "user_agent"
      t.index [ "endpoint", "p256dh_key", "auth_key" ], name: "idx_on_endpoint_p256dh_key_auth_key_7553014576"
      t.index [ "user_id" ], name: "index_push_subscriptions_on_user_id"
    end

    create_table "rooms", force: :cascade do |t|
      t.string "name"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.string "type", null: false
      t.bigint "creator_id", null: false
    end

    create_table "searches", force: :cascade do |t|
      t.integer "user_id", null: false
      t.string "query", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index [ "user_id" ], name: "index_searches_on_user_id"
    end

    create_table "users", force: :cascade do |t|
      t.string "name", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.integer "role", default: 0, null: false
      t.string "email_address"
      t.string "password_digest"
      t.boolean "active", default: true
      t.index [ "email_address" ], name: "index_users_on_email_address", unique: true
    end

    add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
    add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
    add_foreign_key "boosts", "messages"
    add_foreign_key "messages", "rooms"
    add_foreign_key "messages", "users", column: "creator_id"
    add_foreign_key "push_subscriptions", "users"
    add_foreign_key "searches", "users"

    execute <<-SQL
      create virtual table message_search_index using fts5(body, tokenize=porter);
    SQL
  end
end
