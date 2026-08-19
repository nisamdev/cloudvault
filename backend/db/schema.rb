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

ActiveRecord::Schema[8.1].define(version: 2026_08_19_000005) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "families", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "family_storage_quota", default: 2147483648, null: false
    t.bigint "family_storage_used", default: 0, null: false
    t.string "name", null: false
    t.bigint "owner_id", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_families_on_owner_id"
  end

  create_table "family_invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.bigint "family_id", null: false
    t.bigint "invited_by_id", null: false
    t.datetime "revoked_at"
    t.string "role", default: "viewer", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["family_id", "email"], name: "index_family_invitations_pending", unique: true, where: "((accepted_at IS NULL) AND (revoked_at IS NULL))"
    t.index ["family_id"], name: "index_family_invitations_on_family_id"
    t.index ["invited_by_id"], name: "index_family_invitations_on_invited_by_id"
    t.index ["token_digest"], name: "index_family_invitations_on_token_digest", unique: true
    t.check_constraint "role::text = ANY (ARRAY['admin'::character varying, 'editor'::character varying, 'viewer'::character varying]::text[])", name: "family_invitations_role_check"
  end

  create_table "family_members", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "family_id", null: false
    t.datetime "joined_at"
    t.string "role", default: "viewer", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["family_id", "user_id"], name: "index_family_members_on_family_id_and_user_id", unique: true
    t.index ["family_id"], name: "index_family_members_on_family_id"
    t.index ["user_id"], name: "index_family_members_on_user_id"
    t.check_constraint "role::text = ANY (ARRAY['owner'::character varying, 'admin'::character varying, 'editor'::character varying, 'viewer'::character varying]::text[])", name: "family_members_role_check"
  end

  create_table "refresh_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "ip_address"
    t.datetime "last_used_at"
    t.bigint "replaced_by_id"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["replaced_by_id"], name: "index_refresh_tokens_on_replaced_by_id"
    t.index ["token_digest"], name: "index_refresh_tokens_on_token_digest", unique: true
    t.index ["user_id", "revoked_at"], name: "index_refresh_tokens_on_user_id_and_revoked_at"
    t.index ["user_id"], name: "index_refresh_tokens_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "full_name"
    t.datetime "last_signed_in_at"
    t.string "oauth_id"
    t.string "oauth_provider"
    t.string "password_digest"
    t.bigint "storage_quota", default: 268435456, null: false
    t.bigint "storage_used", default: 0, null: false
    t.string "timezone", default: "UTC", null: false
    t.boolean "two_factor_enabled", default: false, null: false
    t.string "two_factor_secret"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["oauth_provider", "oauth_id"], name: "index_users_on_oauth_provider_and_oauth_id", unique: true, where: "(oauth_provider IS NOT NULL)"
  end

  add_foreign_key "families", "users", column: "owner_id"
  add_foreign_key "family_invitations", "families"
  add_foreign_key "family_invitations", "users", column: "invited_by_id"
  add_foreign_key "family_members", "families"
  add_foreign_key "family_members", "users"
  add_foreign_key "refresh_tokens", "refresh_tokens", column: "replaced_by_id"
  add_foreign_key "refresh_tokens", "users"
end
