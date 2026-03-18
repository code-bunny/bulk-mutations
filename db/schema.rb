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

ActiveRecord::Schema[8.1].define(version: 2026_03_18_120000) do
  create_table "bulk_operations", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "error_url"
    t.integer "failed_rows"
    t.string "idempotency_key"
    t.integer "processed_rows"
    t.string "result_url"
    t.text "results_data"
    t.datetime "started_at"
    t.integer "status"
    t.integer "successful_rows"
    t.integer "total_rows"
    t.datetime "updated_at", null: false
  end

  create_table "custom_field_validation_options", force: :cascade do |t|
    t.text "allowed_values"
    t.datetime "created_at", null: false
    t.integer "custom_field_id", null: false
    t.integer "max_length"
    t.integer "min_length"
    t.string "pattern"
    t.boolean "required"
    t.datetime "updated_at", null: false
    t.index ["custom_field_id"], name: "index_custom_field_validation_options_on_custom_field_id"
  end

  create_table "custom_fields", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "custom_field_validation_options", "custom_fields"
end
