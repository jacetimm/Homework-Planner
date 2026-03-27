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

ActiveRecord::Schema[7.2].define(version: 2026_03_26_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "assignment_alerts", force: :cascade do |t|
    t.string "user_email", null: false
    t.string "course_work_id", null: false
    t.string "alert_type", default: "urgent_reminder", null: false
    t.datetime "sent_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_email", "course_work_id", "alert_type", "sent_at"], name: "idx_assignment_alerts_dedup"
    t.index ["user_id"], name: "index_assignment_alerts_on_user_id"
  end

  create_table "assignment_estimates", force: :cascade do |t|
    t.string "course_work_id", null: false
    t.string "user_email", null: false
    t.integer "estimated_minutes", null: false
    t.string "reasoning"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "microtasks"
    t.text "description"
    t.integer "materials_count", default: 0, null: false
    t.integer "max_points"
    t.json "materials_metadata"
    t.string "title"
    t.date "due_date"
    t.string "class_name"
    t.bigint "user_id"
    t.index ["course_work_id", "user_email"], name: "index_assignment_estimates_on_course_work_id_and_user_email", unique: true
    t.index ["user_id"], name: "index_assignment_estimates_on_user_id"
  end

  create_table "assignment_reestimates", force: :cascade do |t|
    t.string "course_work_id", null: false
    t.string "user_email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_email", "course_work_id"], name: "index_assignment_reestimates_on_user_email_and_course_work_id"
    t.index ["user_email", "created_at"], name: "index_assignment_reestimates_on_user_email_and_created_at"
    t.index ["user_id"], name: "index_assignment_reestimates_on_user_id"
  end

  create_table "calendar_caches", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.json "raw_blocks_data", default: []
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_calendar_caches_on_user_id", unique: true
  end

  create_table "classroom_caches", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.json "courses_data", default: []
    t.json "assignments_data", default: []
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_classroom_caches_on_user_id", unique: true
  end

  create_table "study_sessions", force: :cascade do |t|
    t.string "course_work_id", null: false
    t.string "user_email", null: false
    t.string "assignment_title", null: false
    t.string "course_name"
    t.integer "estimated_minutes"
    t.integer "actual_minutes"
    t.datetime "started_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_email", "course_work_id"], name: "index_study_sessions_on_user_email_and_course_work_id"
    t.index ["user_id"], name: "index_study_sessions_on_user_id"
  end

  create_table "user_settings", force: :cascade do |t|
    t.string "user_email"
    t.time "study_start_time"
    t.time "study_end_time"
    t.integer "break_frequency"
    t.integer "break_duration"
    t.json "hard_subjects"
    t.json "extracurricular_blocks"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "block_google_calendar_events", default: true, null: false
    t.json "calendar_ignored_keywords", default: [], null: false
    t.json "ignored_google_calendar_ids", default: [], null: false
    t.json "calendar_ignore_rules", default: [], null: false
    t.integer "streak_count", default: 0, null: false
    t.date "streak_last_date"
    t.integer "max_minutes_per_subject", default: 45
    t.bigint "user_id"
    t.boolean "onboarding_completed", default: true, null: false
    t.boolean "show_all_features", default: false, null: false
    t.integer "visits_count", default: 0, null: false
    t.datetime "first_visited_at"
    t.date "last_visit_date"
    t.string "color_theme", default: "auto", null: false
    t.index ["user_email"], name: "index_user_settings_on_user_email"
    t.index ["user_id"], name: "index_user_settings_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "name"
    t.string "avatar_url"
    t.string "google_uid", null: false
    t.text "access_token"
    t.text "refresh_token"
    t.datetime "token_expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "timezone", default: "Eastern Time (US & Canada)", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["google_uid"], name: "index_users_on_google_uid", unique: true
  end

  add_foreign_key "assignment_alerts", "users"
  add_foreign_key "assignment_estimates", "users"
  add_foreign_key "assignment_reestimates", "users"
  add_foreign_key "calendar_caches", "users"
  add_foreign_key "classroom_caches", "users"
  add_foreign_key "study_sessions", "users"
  add_foreign_key "user_settings", "users"
end
