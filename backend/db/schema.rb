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

ActiveRecord::Schema[8.1].define(version: 2026_08_28_043500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "access_grants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.bigint "granted_by_id", null: false
    t.bigint "resource_id", null: false
    t.string "resource_type", null: false
    t.string "role", default: "viewer", null: false
    t.bigint "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.index ["granted_by_id"], name: "index_access_grants_on_granted_by_id"
    t.index ["resource_type", "resource_id", "subject_type", "subject_id"], name: "index_access_grants_on_resource_and_subject", unique: true
    t.index ["resource_type", "resource_id"], name: "index_access_grants_on_resource"
    t.index ["subject_type", "subject_id"], name: "index_access_grants_on_subject"
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

  create_table "expiry_reminders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "due_on", null: false
    t.string "field_key", null: false
    t.datetime "sent_at", null: false
    t.integer "threshold", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "vault_record_id", null: false
    t.index ["user_id"], name: "index_expiry_reminders_on_user_id"
    t.index ["vault_record_id", "user_id", "field_key", "due_on", "threshold"], name: "index_expiry_reminders_on_what_was_sent", unique: true
    t.index ["vault_record_id"], name: "index_expiry_reminders_on_vault_record_id"
  end

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
    t.datetime "declined_at"
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.bigint "family_id", null: false
    t.bigint "invited_by_id", null: false
    t.datetime "revoked_at"
    t.string "role", default: "viewer", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["family_id", "email"], name: "index_family_invitations_pending", unique: true, where: "((accepted_at IS NULL) AND (revoked_at IS NULL) AND (declined_at IS NULL))"
    t.index ["family_id"], name: "index_family_invitations_on_family_id"
    t.index ["invited_by_id"], name: "index_family_invitations_on_invited_by_id"
    t.index ["token_digest"], name: "index_family_invitations_on_token_digest", unique: true
    t.check_constraint "role::text = ANY (ARRAY['admin'::character varying::text, 'editor'::character varying::text, 'viewer'::character varying::text])", name: "family_invitations_role_check"
  end

  create_table "family_members", force: :cascade do |t|
    t.boolean "can_use_vault"
    t.datetime "created_at", null: false
    t.bigint "family_id", null: false
    t.datetime "joined_at"
    t.string "role", default: "viewer", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "vault_note"
    t.index ["family_id", "user_id"], name: "index_family_members_on_family_id_and_user_id", unique: true
    t.index ["family_id"], name: "index_family_members_on_family_id"
    t.index ["user_id"], name: "index_family_members_on_user_id"
    t.check_constraint "role::text = ANY (ARRAY['owner'::character varying::text, 'admin'::character varying::text, 'editor'::character varying::text, 'viewer'::character varying::text])", name: "family_members_role_check"
  end

  create_table "file_labels", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "label_id", null: false
    t.bigint "stored_file_id", null: false
    t.datetime "updated_at", null: false
    t.index ["label_id"], name: "index_file_labels_on_label_id"
    t.index ["stored_file_id", "label_id"], name: "index_file_labels_on_stored_file_id_and_label_id", unique: true
    t.index ["stored_file_id"], name: "index_file_labels_on_stored_file_id"
  end

  create_table "file_versions", force: :cascade do |t|
    t.string "checksum"
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.bigint "size", default: 0, null: false
    t.bigint "stored_file_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["created_by_id"], name: "index_file_versions_on_created_by_id"
    t.index ["stored_file_id", "version_number"], name: "index_file_versions_on_stored_file_id_and_version_number", unique: true
    t.index ["stored_file_id"], name: "index_file_versions_on_stored_file_id"
  end

  create_table "folders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "family_id"
    t.boolean "locked", default: false, null: false
    t.string "name", null: false
    t.bigint "parent_id"
    t.datetime "trashed_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index "family_id, COALESCE(parent_id, (0)::bigint), lower((name)::text)", name: "index_folders_unique_name_in_family", unique: true, where: "((trashed_at IS NULL) AND (family_id IS NOT NULL))"
    t.index "user_id, COALESCE(parent_id, (0)::bigint), lower((name)::text)", name: "index_folders_unique_name_personal", unique: true, where: "((trashed_at IS NULL) AND (family_id IS NULL))"
    t.index ["family_id"], name: "index_folders_on_family_id"
    t.index ["name"], name: "index_folders_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["parent_id"], name: "index_folders_on_parent_id"
    t.index ["user_id", "locked"], name: "index_folders_on_user_id_and_locked"
    t.index ["user_id"], name: "index_folders_on_user_id"
  end

  create_table "labels", force: :cascade do |t|
    t.string "color", default: "#6366F1", null: false
    t.datetime "created_at", null: false
    t.bigint "family_id"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["family_id", "name"], name: "index_labels_on_family_id_and_name", unique: true, where: "(family_id IS NOT NULL)"
    t.index ["family_id"], name: "index_labels_on_family_id"
    t.index ["user_id", "name"], name: "index_labels_on_user_id_and_name", unique: true, where: "(family_id IS NULL)"
    t.index ["user_id"], name: "index_labels_on_user_id"
  end

  create_table "private_vaults", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "passphrase_salt", null: false
    t.text "passphrase_sealed_key", null: false
    t.datetime "recovery_key_shown_at"
    t.string "recovery_salt", null: false
    t.text "recovery_sealed_key", null: false
    t.datetime "unlocked_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_private_vaults_on_user_id", unique: true
  end

  create_table "record_attachments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.bigint "stored_file_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "vault_record_id", null: false
    t.index ["stored_file_id"], name: "index_record_attachments_on_stored_file_id"
    t.index ["vault_record_id", "stored_file_id"], name: "index_record_attachments_on_vault_record_id_and_stored_file_id", unique: true
    t.index ["vault_record_id"], name: "index_record_attachments_on_vault_record_id"
  end

  create_table "record_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "linked_record_id", null: false
    t.string "relation", default: "related_to", null: false
    t.datetime "updated_at", null: false
    t.bigint "vault_record_id", null: false
    t.index ["linked_record_id"], name: "index_record_links_on_linked_record_id"
    t.index ["vault_record_id", "linked_record_id"], name: "index_record_links_on_vault_record_id_and_linked_record_id", unique: true
    t.index ["vault_record_id"], name: "index_record_links_on_vault_record_id"
  end

  create_table "record_secrets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "kdf", default: {}, null: false
    t.string "key", null: false
    t.binary "sealed", null: false
    t.datetime "updated_at", null: false
    t.bigint "vault_record_id", null: false
    t.index ["vault_record_id", "key"], name: "index_record_secrets_on_vault_record_id_and_key", unique: true
    t.index ["vault_record_id"], name: "index_record_secrets_on_vault_record_id"
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

  create_table "secret_versions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "record_secret_id", null: false
    t.datetime "replaced_at", null: false
    t.binary "sealed", null: false
    t.datetime "updated_at", null: false
    t.index ["record_secret_id", "replaced_at"], name: "index_secret_versions_on_record_secret_id_and_replaced_at"
    t.index ["record_secret_id"], name: "index_secret_versions_on_record_secret_id"
  end

  create_table "shared_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "download_count", default: 0, null: false
    t.datetime "expires_at"
    t.datetime "last_accessed_at"
    t.integer "max_downloads"
    t.string "password_digest"
    t.datetime "revoked_at"
    t.bigint "stored_file_id"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "vault_record_id"
    t.index ["stored_file_id", "revoked_at"], name: "index_shared_links_on_stored_file_id_and_revoked_at"
    t.index ["stored_file_id"], name: "index_shared_links_on_stored_file_id"
    t.index ["token_digest"], name: "index_shared_links_on_token_digest", unique: true
    t.index ["user_id"], name: "index_shared_links_on_user_id"
    t.index ["vault_record_id", "revoked_at"], name: "index_shared_links_on_vault_record_id_and_revoked_at"
    t.index ["vault_record_id"], name: "index_shared_links_on_vault_record_id"
    t.check_constraint "(stored_file_id IS NULL) <> (vault_record_id IS NULL)", name: "shared_links_one_subject"
  end

  create_table "signatures", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_default", default: false, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "name"], name: "index_signatures_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_signatures_on_user_id"
    t.index ["user_id"], name: "index_signatures_one_default_per_user", unique: true, where: "(is_default = true)"
  end

  create_table "stored_files", force: :cascade do |t|
    t.string "camera_make"
    t.string "camera_model"
    t.string "checksum"
    t.datetime "created_at", null: false
    t.boolean "encrypted", default: false, null: false
    t.bigint "family_id"
    t.string "file_type", default: "file", null: false
    t.boolean "file_type_pinned", default: false, null: false
    t.bigint "folder_id"
    t.integer "image_height"
    t.integer "image_width"
    t.datetime "last_accessed_at"
    t.decimal "latitude", precision: 10, scale: 6
    t.boolean "locked", default: false, null: false
    t.decimal "longitude", precision: 10, scale: 6
    t.string "mime_type", null: false
    t.string "name", null: false
    t.virtual "search_vector", type: :tsvector, as: "to_tsvector('english'::regconfig, translate((COALESCE(name, ''::character varying))::text, '_-.'::text, '   '::text))", stored: true
    t.bigint "size", default: 0, null: false
    t.datetime "taken_at"
    t.datetime "trashed_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "version_number", default: 1, null: false
    t.string "visibility", default: "private", null: false
    t.index ["family_id", "created_at"], name: "index_stored_files_on_family_id_and_created_at"
    t.index ["family_id"], name: "index_stored_files_on_family_id"
    t.index ["file_type", "created_at"], name: "index_stored_files_on_file_type_and_created_at"
    t.index ["folder_id"], name: "index_stored_files_on_folder_id"
    t.index ["latitude", "longitude"], name: "index_stored_files_on_coordinates", where: "((latitude IS NOT NULL) AND (longitude IS NOT NULL))"
    t.index ["name"], name: "index_stored_files_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["search_vector"], name: "index_stored_files_on_search_vector", using: :gin
    t.index ["taken_at"], name: "index_stored_files_on_taken_at"
    t.index ["user_id", "locked"], name: "index_stored_files_on_user_id_and_locked"
    t.index ["user_id", "trashed_at"], name: "index_stored_files_on_user_id_and_trashed_at"
    t.index ["user_id"], name: "index_stored_files_on_user_id"
    t.check_constraint "file_type::text = ANY (ARRAY['file'::character varying, 'image'::character varying]::text[])", name: "stored_files_file_type_check"
    t.check_constraint "visibility::text = ANY (ARRAY['private'::character varying, 'family'::character varying, 'shared_link'::character varying]::text[])", name: "stored_files_visibility_check"
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.bigint "current_family_id"
    t.string "email", null: false
    t.string "full_name"
    t.datetime "last_signed_in_at"
    t.string "oauth_id"
    t.string "oauth_provider"
    t.string "password_digest"
    t.string "reminder_scope", default: "family", null: false
    t.boolean "reminders_enabled", default: true, null: false
    t.bigint "storage_quota", default: 268435456, null: false
    t.bigint "storage_used", default: 0, null: false
    t.string "timezone", default: "UTC", null: false
    t.boolean "two_factor_enabled", default: false, null: false
    t.string "two_factor_secret"
    t.datetime "updated_at", null: false
    t.boolean "videos_enabled", default: false, null: false
    t.index ["current_family_id"], name: "index_users_on_current_family_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["oauth_provider", "oauth_id"], name: "index_users_on_oauth_provider_and_oauth_id", unique: true, where: "(oauth_provider IS NOT NULL)"
  end

  create_table "vault_records", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.bigint "family_id"
    t.bigint "folder_id"
    t.boolean "locked", default: false, null: false
    t.string "record_type", null: false
    t.virtual "search_vector", type: :tsvector, as: "to_tsvector('english'::regconfig, (((COALESCE(title, ''::character varying))::text || ' '::text) || COALESCE((jsonb_path_query_array(data, '$.*'::jsonpath))::text, ''::text)))", stored: true
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "visibility", default: "private", null: false
    t.index ["data"], name: "index_vault_records_on_data", using: :gin
    t.index ["family_id", "archived_at"], name: "index_vault_records_on_family_id_and_archived_at"
    t.index ["family_id"], name: "index_vault_records_on_family_id"
    t.index ["folder_id"], name: "index_vault_records_on_folder_id"
    t.index ["search_vector"], name: "index_vault_records_on_search_vector", using: :gin
    t.index ["user_id", "locked"], name: "index_vault_records_on_user_id_and_locked"
    t.index ["user_id", "record_type"], name: "index_vault_records_on_user_id_and_record_type"
    t.index ["user_id"], name: "index_vault_records_on_user_id"
  end

  add_foreign_key "access_grants", "users", column: "granted_by_id"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "expiry_reminders", "users"
  add_foreign_key "expiry_reminders", "vault_records"
  add_foreign_key "families", "users", column: "owner_id"
  add_foreign_key "family_invitations", "families"
  add_foreign_key "family_invitations", "users", column: "invited_by_id"
  add_foreign_key "family_members", "families"
  add_foreign_key "family_members", "users"
  add_foreign_key "file_labels", "labels"
  add_foreign_key "file_labels", "stored_files"
  add_foreign_key "file_versions", "stored_files"
  add_foreign_key "file_versions", "users", column: "created_by_id"
  add_foreign_key "folders", "families"
  add_foreign_key "folders", "folders", column: "parent_id"
  add_foreign_key "folders", "users"
  add_foreign_key "labels", "families"
  add_foreign_key "labels", "users"
  add_foreign_key "private_vaults", "users"
  add_foreign_key "record_attachments", "stored_files"
  add_foreign_key "record_attachments", "vault_records"
  add_foreign_key "record_links", "vault_records"
  add_foreign_key "record_links", "vault_records", column: "linked_record_id"
  add_foreign_key "record_secrets", "vault_records"
  add_foreign_key "refresh_tokens", "refresh_tokens", column: "replaced_by_id"
  add_foreign_key "refresh_tokens", "users"
  add_foreign_key "secret_versions", "record_secrets"
  add_foreign_key "shared_links", "stored_files"
  add_foreign_key "shared_links", "users"
  add_foreign_key "shared_links", "vault_records"
  add_foreign_key "signatures", "users"
  add_foreign_key "stored_files", "families"
  add_foreign_key "stored_files", "folders"
  add_foreign_key "stored_files", "users"
  add_foreign_key "users", "families", column: "current_family_id", on_delete: :nullify
  add_foreign_key "vault_records", "families"
  add_foreign_key "vault_records", "folders"
  add_foreign_key "vault_records", "users"
end
