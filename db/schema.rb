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

ActiveRecord::Schema[7.2].define(version: 2026_03_17_100001) do
  create_table "assignment_alerts", force: :cascade do |t|
    t.string "user_email", null: false
    t.string "course_work_id", null: false
    t.string "alert_type", default: "urgent_reminder", null: false
    t.datetime "sent_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_email", "course_work_id", "alert_type", "sent_at"], name: "idx_assignment_alerts_dedup"
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
    t.index ["course_work_id", "user_email"], name: "index_assignment_estimates_on_course_work_id_and_user_email", unique: true
  end

  create_table "assignment_reestimates", force: :cascade do |t|
    t.string "course_work_id", null: false
    t.string "user_email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_email", "course_work_id"], name: "index_assignment_reestimates_on_user_email_and_course_work_id"
    t.index ["user_email", "created_at"], name: "index_assignment_reestimates_on_user_email_and_created_at"
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
    t.index ["user_email", "course_work_id"], name: "index_study_sessions_on_user_email_and_course_work_id"
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
    t.integer "max_minutes_per_subject", default: 45
    t.integer "streak_count", default: 0, null: false
    t.date "streak_last_date"
    t.index ["user_email"], name: "index_user_settings_on_user_email"
  end
end
