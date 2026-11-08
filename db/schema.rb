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

ActiveRecord::Schema[8.1].define(version: 2026_11_08_040000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "checks", force: :cascade do |t|
    t.bigint "control_id", null: false
    t.bigint "integration_id", null: false
    t.string "status"
    t.datetime "checked_at"
    t.text "details"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "scan_id"
    t.index ["control_id"], name: "index_checks_on_control_id"
    t.index ["integration_id"], name: "index_checks_on_integration_id"
    t.index ["scan_id"], name: "index_checks_on_scan_id"
  end

  create_table "controls", force: :cascade do |t|
    t.string "key"
    t.string "title"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "evidences", force: :cascade do |t|
    t.bigint "check_id", null: false
    t.string "resource"
    t.jsonb "payload"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["check_id"], name: "index_evidences_on_check_id"
  end

  create_table "integrations", force: :cascade do |t|
    t.string "name"
    t.string "provider"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "scans", force: :cascade do |t|
    t.bigint "integration_id", null: false
    t.string "status", default: "running"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["integration_id"], name: "index_scans_on_integration_id"
  end

  add_foreign_key "checks", "controls"
  add_foreign_key "checks", "integrations"
  add_foreign_key "checks", "scans"
  add_foreign_key "evidences", "checks"
  add_foreign_key "scans", "integrations"
end
