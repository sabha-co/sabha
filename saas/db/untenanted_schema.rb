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

ActiveRecord::Schema[8.2].define(version: 2026_03_12_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "auth_codes", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.integer "global_identity_id", null: false
    t.integer "purpose", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_auth_codes_on_code", unique: true
    t.index ["expires_at"], name: "index_auth_codes_on_expires_at"
    t.index ["global_identity_id"], name: "index_auth_codes_on_global_identity_id"
  end

  create_table "global_identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "name"
    t.boolean "superadmin", default: false, null: false
    t.string "unconfirmed_email"
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.index ["email_address"], name: "index_global_identities_on_email_address", unique: true
    t.index ["superadmin"], name: "index_global_identities_on_superadmin"
    t.index ["verified_at"], name: "index_global_identities_on_verified_at"
  end

  create_table "global_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.integer "global_identity_id", null: false
    t.string "ip_address"
    t.datetime "last_active_at"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["expires_at"], name: "index_global_sessions_on_expires_at"
    t.index ["global_identity_id"], name: "index_global_sessions_on_global_identity_id"
    t.index ["token"], name: "index_global_sessions_on_token", unique: true
  end

  create_table "workspace_external_id_sequences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "value", default: 1000000, null: false
  end

  create_table "workspace_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "global_identity_id", null: false
    t.integer "position"
    t.string "tenant", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["global_identity_id", "position"], name: "index_workspace_memberships_on_global_identity_id_and_position"
    t.index ["global_identity_id", "tenant"], name: "index_workspace_memberships_on_global_identity_id_and_tenant", unique: true
    t.index ["global_identity_id"], name: "index_workspace_memberships_on_global_identity_id"
    t.index ["tenant"], name: "index_workspace_memberships_on_tenant"
  end

  create_table "workspaces", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "creator_id", null: false
    t.bigint "external_id", null: false
    t.boolean "has_logo", default: false, null: false
    t.string "name", null: false
    t.string "slug"
    t.datetime "suspended_at"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_workspaces_on_creator_id"
    t.index ["external_id"], name: "index_workspaces_on_external_id", unique: true
    t.index ["slug"], name: "index_workspaces_on_slug", unique: true
    t.index ["suspended_at"], name: "index_workspaces_on_suspended_at"
  end

  add_foreign_key "auth_codes", "global_identities"
  add_foreign_key "global_sessions", "global_identities"
  add_foreign_key "workspace_memberships", "global_identities"
  add_foreign_key "workspaces", "global_identities", column: "creator_id"
end
