# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.2].define(version: 2025_12_05_182543) do
  create_table "accounts", force: :cascade do |t|
    t.boolean "active", default: true
    t.string "auth_method", default: "password"
    t.datetime "created_at", null: false
    t.text "custom_styles"
    t.string "join_code", null: false
    t.string "name", null: false
    t.json "settings"
    t.datetime "updated_at", null: false
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "auth_tokens", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "token"
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_auth_tokens_on_user_id"
  end

  create_table "bans", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["ip_address"], name: "index_bans_on_ip_address"
    t.index ["user_id"], name: "index_bans_on_user_id"
  end

  create_table "blocks", force: :cascade do |t|
    t.integer "blocked_id", null: false
    t.integer "blocker_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked_id"], name: "index_blocks_on_blocked_id"
    t.index ["blocker_id", "blocked_id"], name: "index_blocks_on_blocker_id_and_blocked_id", unique: true
    t.index ["blocker_id"], name: "index_blocks_on_blocker_id"
  end

  create_table "bookmarks", force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.integer "message_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["message_id"], name: "index_bookmarks_on_message_id"
    t.index ["user_id", "message_id", "active"], name: "index_bookmarks_on_user_message_active"
    t.index ["user_id"], name: "index_bookmarks_on_user_id"
  end

  create_table "boosts", force: :cascade do |t|
    t.boolean "active", default: true
    t.integer "booster_id", null: false
    t.string "content", limit: 16, null: false
    t.datetime "created_at", null: false
    t.integer "message_id", null: false
    t.datetime "updated_at", null: false
    t.index ["booster_id"], name: "index_boosts_on_booster_id"
    t.index ["message_id", "active", "created_at"], name: "index_boosts_on_message_active_created"
    t.index ["message_id"], name: "index_boosts_on_message_id"
  end

  create_table "library_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_library_categories_on_slug", unique: true
  end

  create_table "library_classes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "creator", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_library_classes_on_position"
    t.index ["slug"], name: "index_library_classes_on_slug", unique: true
  end

  create_table "library_classes_categories", id: false, force: :cascade do |t|
    t.integer "library_category_id", null: false
    t.integer "library_class_id", null: false
    t.index ["library_category_id"], name: "index_library_classes_categories_on_library_category_id"
    t.index ["library_class_id", "library_category_id"], name: "index_library_classes_categories_on_class_and_category", unique: true
    t.index ["library_class_id"], name: "index_library_classes_categories_on_library_class_id"
  end

  create_table "library_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.boolean "featured", default: false, null: false
    t.integer "featured_position", default: 0, null: false
    t.datetime "last_watched_at"
    t.integer "library_class_id", null: false
    t.decimal "padding", precision: 5, scale: 2, default: "56.25", null: false
    t.integer "played_seconds", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.string "quality"
    t.datetime "updated_at", null: false
    t.string "vimeo_hash"
    t.string "vimeo_id", null: false
    t.index ["featured"], name: "index_library_sessions_on_featured"
    t.index ["featured_position"], name: "index_library_sessions_on_featured_position"
    t.index ["library_class_id"], name: "index_library_sessions_on_library_class_id"
    t.index ["position"], name: "index_library_sessions_on_position"
    t.index ["vimeo_id"], name: "index_library_sessions_on_vimeo_id"
  end

  create_table "library_watch_histories", force: :cascade do |t|
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.datetime "last_watched_at"
    t.integer "library_session_id", null: false
    t.integer "played_seconds", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["library_session_id", "user_id"], name: "index_library_watch_histories_on_session_and_user", unique: true
  end

  create_table "mailkick_subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "list"
    t.integer "subscriber_id"
    t.string "subscriber_type"
    t.datetime "updated_at", null: false
    t.index ["subscriber_type", "subscriber_id", "list"], name: "index_mailkick_subscriptions_on_subscriber_and_list", unique: true
  end

  create_table "memberships", force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "connected_at"
    t.integer "connections", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "involvement", default: "mentions"
    t.datetime "notified_until"
    t.integer "room_id", null: false
    t.datetime "unread_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["room_id", "created_at"], name: "index_memberships_on_room_id_and_created_at"
    t.index ["room_id", "user_id", "involvement"], name: "index_memberships_on_room_user_involvement"
    t.index ["room_id", "user_id"], name: "index_memberships_on_room_id_and_user_id", unique: true
    t.index ["room_id"], name: "index_memberships_on_room_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "mentions", id: false, force: :cascade do |t|
    t.integer "message_id", null: false
    t.integer "user_id", null: false
    t.index ["message_id", "user_id"], name: "index_mentions_on_message_id_and_user_id"
    t.index ["message_id"], name: "index_mentions_on_message_id"
    t.index ["user_id", "message_id"], name: "index_mentions_on_user_id_and_message_id"
    t.index ["user_id"], name: "index_mentions_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.boolean "active", default: true
    t.string "client_message_id", null: false
    t.datetime "created_at", null: false
    t.integer "creator_id", null: false
    t.boolean "mentions_everyone", default: false, null: false
    t.integer "room_id", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "room_id", "created_at"], name: "index_messages_on_active_room_created"
    t.index ["created_at"], name: "index_messages_on_created_at"
    t.index ["creator_id"], name: "index_messages_on_creator_id"
    t.index ["room_id", "created_at"], name: "index_messages_on_room_id_and_created_at"
    t.index ["room_id", "mentions_everyone"], name: "index_messages_on_room_id_and_mentions_everyone", where: "mentions_everyone = true"
    t.index ["room_id"], name: "index_messages_on_room_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.string "auth_key"
    t.datetime "created_at", null: false
    t.string "endpoint"
    t.string "p256dh_key"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["endpoint", "p256dh_key", "auth_key"], name: "idx_on_endpoint_p256dh_key_auth_key_7553014576"
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.bigint "creator_id", null: false
    t.datetime "last_active_at"
    t.integer "messages_count", default: 0
    t.string "name"
    t.integer "parent_message_id"
    t.string "slug"
    t.string "sortable_name"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_message_id"], name: "index_rooms_on_parent_message_id_unique_thread", unique: true, where: "type = 'Rooms::Thread' AND parent_message_id IS NOT NULL"
    t.index ["slug"], name: "index_rooms_on_slug", unique: true, where: "slug IS NOT NULL"
  end

  create_table "searches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "creator_id"
    t.string "query", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["creator_id"], name: "index_searches_on_creator_id"
    t.index ["user_id"], name: "index_searches_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "last_active_at", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["token"], name: "index_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "ascii_name"
    t.string "avatar_url"
    t.text "bio"
    t.string "bot_token"
    t.datetime "created_at", null: false
    t.string "email_address"
    t.datetime "last_authenticated_at"
    t.string "linkedin_url"
    t.string "linkedin_username"
    t.datetime "membership_started_at"
    t.string "name", null: false
    t.bigint "order_id"
    t.string "password_digest"
    t.string "personal_url"
    t.text "preferences", default: "{}"
    t.integer "role", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "twitter_url"
    t.string "twitter_username"
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.index ["bot_token"], name: "index_users_on_bot_token", unique: true
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["order_id"], name: "index_users_on_order_id", unique: true, where: "order_id IS NOT NULL"
  end

  create_table "webhook_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type"
    t.text "payload"
    t.datetime "processed_at"
    t.string "source"
    t.datetime "updated_at", null: false
  end

  create_table "webhooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "receives"
    t.datetime "updated_at", null: false
    t.string "url"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_webhooks_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "auth_tokens", "users"
  add_foreign_key "bans", "users"
  add_foreign_key "blocks", "users", column: "blocked_id"
  add_foreign_key "blocks", "users", column: "blocker_id"
  add_foreign_key "bookmarks", "messages"
  add_foreign_key "bookmarks", "users"
  add_foreign_key "boosts", "messages"
  add_foreign_key "library_classes_categories", "library_categories"
  add_foreign_key "library_classes_categories", "library_classes"
  add_foreign_key "library_sessions", "library_classes"
  add_foreign_key "library_watch_histories", "library_sessions"
  add_foreign_key "library_watch_histories", "users"
  add_foreign_key "mentions", "messages"
  add_foreign_key "mentions", "users"
  add_foreign_key "messages", "rooms"
  add_foreign_key "messages", "users", column: "creator_id"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "searches", "users"
  add_foreign_key "searches", "users", column: "creator_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "webhooks", "users"

  # Virtual tables defined in this database.
  # Note that virtual tables may not work with other database engines. Be careful if changing database.
  create_virtual_table "message_search_index", "fts5", ["body", "tokenize=porter"]
end
