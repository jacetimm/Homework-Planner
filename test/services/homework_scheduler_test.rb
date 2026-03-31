require "test_helper"

class HomeworkSchedulerTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  # 10am on a fixed date — safely before the 7pm study window
  FROZEN_AT   = Time.zone.local(2026, 3, 24, 10, 0, 0)
  STUDY_START = Time.parse("19:00:00")   # 1140 minutes
  STUDY_END   = Time.parse("22:00:00")   # 1320 minutes

  setup    { travel_to FROZEN_AT }
  teardown { travel_back }

  # ── Helpers ──────────────────────────────────────────────────────────────

  # break_frequency: 180 keeps the 3-hour window break-free while avoiding
  # Float::INFINITY.to_i, which raises FloatDomainError in Ruby 3.x.
  def default_scheduler(**opts)
    HomeworkScheduler.new(
      nightly_capacity: 120,
      tonight_capacity: 120,
      study_start_time: STUDY_START,
      study_end_time:   STUDY_END,
      break_frequency:  180,
      break_duration:   10,
      **opts
    )
  end

  def make_assignment(
    course_work_id: "cw1", title: "Essay", class_name: "English",
    estimated_minutes: 30, due_in_days: 2, state: nil
  )
    {
      course_work_id:     course_work_id,
      title:              title,
      class_name:         class_name,
      estimated_minutes:  estimated_minutes,
      due_date:           Date.current + due_in_days,
      state:              state,
      assignment_link:    nil,
      materials_metadata: []
    }
  end

  def today_assignments(result)
    result[Date.current.to_s][:assignments]
  end

  # ── Priority classification ──────────────────────────────────────────────

  test "assignment due today is classified as urgent" do
    result = default_scheduler.schedule([make_assignment(due_in_days: 0)])
    assert_equal "urgent", today_assignments(result).first[:priority]
  end

  test "assignment due tomorrow is classified as urgent" do
    result = default_scheduler.schedule([make_assignment(due_in_days: 1)])
    assert_equal "urgent", today_assignments(result).first[:priority]
  end

  test "assignment due in 2 days is classified as needs_focus" do
    result = default_scheduler.schedule([make_assignment(due_in_days: 2)])
    assert_equal "needs_focus", today_assignments(result).first[:priority]
  end

  test "assignment due in 5 days is classified as can_wait" do
    result = default_scheduler.schedule([make_assignment(due_in_days: 5)])
    assert_equal "can_wait", today_assignments(result).first[:priority]
  end

  test "hard subject is bumped to needs_focus even when due in 5 days" do
    a = make_assignment(due_in_days: 5, class_name: "Calculus")
    result = default_scheduler(hard_subjects: ["Calculus"]).schedule([a])
    assert_equal "needs_focus", today_assignments(result).first[:priority]
  end

  test "long assignment (over 60 min) becomes needs_focus even when due in 4 days" do
    a = make_assignment(due_in_days: 4, estimated_minutes: 90)
    result = default_scheduler.schedule([a])
    # classify_priority uses full_assignment_minutes, so the tonight entry
    # (which may be a 45-min split) still reflects the full 90 min.
    assert_equal "needs_focus", today_assignments(result).first[:priority]
  end

  # ── Capacity / won't fit ─────────────────────────────────────────────────

  test "assignment skipped tonight appears in wont_fit_tonight" do
    a = make_assignment(due_in_days: 5)
    result = HomeworkScheduler.new(
      nightly_capacity: 120,
      tonight_capacity: 0,
      study_start_time: STUDY_START,
      study_end_time:   STUDY_END,
      break_frequency:  180
    ).schedule([a])
    assert result["wont_fit_tonight"].any? { |x| x[:course_work_id] == "cw1" }
  end

  test "assignment too large for entire 7-day window appears in wont_fit" do
    a = make_assignment(due_in_days: 0, estimated_minutes: 500)
    result = HomeworkScheduler.new(
      nightly_capacity: 50,
      tonight_capacity: 50,
      study_start_time: STUDY_START,
      study_end_time:   STUDY_END,
      break_frequency:  180
    ).schedule([a])
    assert result["wont_fit"].any? { |x| x[:course_work_id] == "cw1" }
  end

  test "turned-in assignments are excluded from the schedule entirely" do
    a = make_assignment(due_in_days: 0, state: "TURNED_IN")
    result = default_scheduler.schedule([a])
    (0..6).each { |i| assert_empty result[(Date.current + i).to_s][:assignments] }
    assert_empty result["wont_fit"]
  end

  test "assignments due more than 7 days away are not scheduled" do
    a = make_assignment(due_in_days: 8)
    result = default_scheduler.schedule([a])
    (0..6).each { |i| assert_empty result[(Date.current + i).to_s][:assignments] }
  end

  test "overdue assignment is scheduled tonight" do
    a = make_assignment(due_in_days: -1)
    result = default_scheduler.schedule([a])
    assert today_assignments(result).any? { |e| e[:course_work_id] == "cw1" }
  end

  # ── Split logic ───────────────────────────────────────────────────────────

  test "assignment is split across nights when it exceeds max_per_subject" do
    # 90 min, max 45 per subject, due in 3 days → 2 nights needed
    a = make_assignment(due_in_days: 3, estimated_minutes: 90)
    result = default_scheduler(max_per_subject: 45).schedule([a])

    tonight_min = today_assignments(result).sum { |e| e[:minutes] }
    assert_operator tonight_min, :<=, 45

    total_scheduled = (0..6).sum do |i|
      result[(Date.current + i).to_s][:assignments]
        .select { |e| e[:course_work_id] == "cw1" }
        .sum    { |e| e[:minutes] }
    end
    assert_equal 90, total_scheduled
  end

  # ── Absorb logic ──────────────────────────────────────────────────────────

  test "leftover under 15 min is absorbed into current night rather than split" do
    # 47 min, max 45: leftover = 2 < 15 → absorbed → all 47 scheduled tonight
    a = make_assignment(due_in_days: 2, estimated_minutes: 47)
    result = default_scheduler(max_per_subject: 45).schedule([a])

    tonight_entries = today_assignments(result).select { |e| e[:course_work_id] == "cw1" }
    assert_equal 1, tonight_entries.size
    assert_equal 47, tonight_entries.first[:minutes]
  end

  test "leftover of exactly 15 min is absorbed into the current night" do
    # 60 min, max 45: leftover = 15 (<= 15) → absorbed → all 60 scheduled tonight
    a = make_assignment(due_in_days: 3, estimated_minutes: 60)
    result = default_scheduler(max_per_subject: 45).schedule([a])

    tonight_entries = today_assignments(result).select { |e| e[:course_work_id] == "cw1" }
    assert_equal 1, tonight_entries.size
    assert_equal 60, tonight_entries.first[:minutes]
  end

  test "leftover over 15 min still creates a proper split" do
    a = make_assignment(due_in_days: 3, estimated_minutes: 61)
    result = default_scheduler(max_per_subject: 45).schedule([a])

    tonight_entries = today_assignments(result).select { |e| e[:course_work_id] == "cw1" }
    assert_equal 1, tonight_entries.size
    assert_equal 45, tonight_entries.first[:minutes]
  end

  test "tiny overflow beyond the nightly cap is not absorbed when assignment exceeds nightly_capacity" do
    a = make_assignment(due_in_days: 2, estimated_minutes: 47)
    result = HomeworkScheduler.new(
      nightly_capacity: 45,
      tonight_capacity: 45,
      study_start_time: STUDY_START,
      study_end_time:   STUDY_END,
      break_frequency:  180,
      break_duration:   10,
      max_per_subject:  45
    ).schedule([a])

    tonight_entries = today_assignments(result).select { |e| e[:course_work_id] == "cw1" }
    assert_equal 1, tonight_entries.size
    assert_equal 45, tonight_entries.first[:minutes]

    tomorrow_entries = result[(Date.current + 1).to_s][:assignments].select { |e| e[:course_work_id] == "cw1" }
    assert_equal 1, tomorrow_entries.size
    assert_equal 2, tomorrow_entries.first[:minutes]
  end

  # ── Buffer day ────────────────────────────────────────────────────────────

  test "buffer day is preserved before due date when schedule allows" do
    # Due in 4 days → preferred_last_night = due_date - 1 = today+3
    # So nothing should land on the due date itself (today+4)
    a = make_assignment(due_in_days: 4)
    result = default_scheduler.schedule([a])
    due_date_str = (Date.current + 4).to_s
    due_day_entries = result[due_date_str][:assignments].select { |e| e[:course_work_id] == "cw1" }
    assert_empty due_day_entries
  end

  # ── Calendar blocks in timeline ───────────────────────────────────────────

  test "calendar block appears in tonight's timeline" do
    a = make_assignment(due_in_days: 0)
    cal_block = { type: "calendar", label: "Soccer", start_m: 1200, end_m: 1230 }

    result = HomeworkScheduler.new(
      nightly_capacity:     120,
      tonight_capacity:     120,
      study_start_time:     STUDY_START,
      study_end_time:       STUDY_END,
      break_frequency:      180,
      break_duration:       10,
      calendar_busy_blocks: [cal_block]
    ).schedule([a])

    timeline  = result[Date.current.to_s][:timeline]
    cal_slots = timeline.select { |s| s[:type] == "calendar" }
    assert_equal 1, cal_slots.size
    assert_equal 1200, cal_slots.first[:start_m]
    assert_equal 1230, cal_slots.first[:end_m]
  end

  test "no study block overlaps with a calendar event in the timeline" do
    # Block covers the first 30 min of the study window (19:00–19:30)
    a = make_assignment(due_in_days: 0, estimated_minutes: 60)
    cal_block = { type: "calendar", label: "Soccer", start_m: 1140, end_m: 1170 }

    result = HomeworkScheduler.new(
      nightly_capacity:     120,
      tonight_capacity:     120,
      study_start_time:     STUDY_START,
      study_end_time:       STUDY_END,
      break_frequency:      180,
      break_duration:       10,
      calendar_busy_blocks: [cal_block]
    ).schedule([a])

    timeline = result[Date.current.to_s][:timeline]
    timeline.select { |s| s[:type] == "study" }.each do |slot|
      assert_operator slot[:start_m], :>=, 1170,
        "Study block at #{slot[:start_m]} overlaps with calendar event ending at 1170"
    end
  end

  test "tiny leftover after a break is absorbed into the current study block" do
    a = make_assignment(title: "Biology Research", class_name: "Biology", due_in_days: 0, estimated_minutes: 36)

    result = HomeworkScheduler.new(
      nightly_capacity: 120,
      tonight_capacity: 120,
      study_start_time: STUDY_START,
      study_end_time:   STUDY_END,
      break_frequency:  30,
      break_duration:   10,
      max_per_subject:  45
    ).schedule([a])

    timeline = result[Date.current.to_s][:timeline]
    study_slots = timeline.select { |slot| slot[:type] == "study" }
    break_slots = timeline.select { |slot| slot[:type] == "break" }

    assert_equal 1, study_slots.size
    assert_equal "Biology Research", study_slots.first[:label]
    assert_equal 36, study_slots.first[:end_m] - study_slots.first[:start_m]
    assert_equal 1, break_slots.size
    assert_equal study_slots.first[:end_m], break_slots.first[:start_m]
  end

  test "assignment is not split across days when it fits within nightly_capacity despite reduced remaining_cap" do
    # Prior assignment consumed 25 min of tonight's 120-min capacity (leaving 95 min).
    # Essay is 60 min with a 45-min per-subject cap — the cap creates a 15-min leftover,
    # but the full assignment fits within nightly_capacity, so the absorb should fire
    # and produce a single tonight entry rather than a 45m/15m day-split.
    prior = make_assignment(course_work_id: "prior", title: "Quick Task", class_name: "Math",
                            estimated_minutes: 25, due_in_days: 0)
    essay = make_assignment(course_work_id: "essay", title: "Essay", class_name: "English",
                            estimated_minutes: 60, due_in_days: 3)

    result = default_scheduler(max_per_subject: 45).schedule([prior, essay])

    essay_tonight = today_assignments(result).select { |e| e[:course_work_id] == "essay" }
    assert_equal 1, essay_tonight.size,
      "Essay should be fully scheduled tonight, not split across days"
    assert_equal 60, essay_tonight.first[:minutes]
    assert_nil essay_tonight.first[:split_plan],
      "split_plan should be absent when the full assignment fits in one night"
  end

  test "pre-break stub absorb defers break when tiny time remains before break" do
    # prior is due today (urgency 2, processed first) and takes 30 min, leaving
    # study_accum=30 when Biology starts.  With break_frequency=45 only 15 min remain
    # before the break.  The stub check (split_minutes<=15) should absorb the full
    # 36m into one block and defer the break until after Biology finishes.
    prior   = make_assignment(course_work_id: "prior", title: "Math HW",   class_name: "Math",
                              estimated_minutes: 30, due_in_days: 0)
    # Biology is due tomorrow so it sorts after the today-due prior assignment.
    biology = make_assignment(course_work_id: "bio",   title: "Biology Research", class_name: "Biology",
                              estimated_minutes: 36, due_in_days: 1)

    result = HomeworkScheduler.new(
      nightly_capacity: 120,
      tonight_capacity: 120,
      study_start_time: STUDY_START,
      study_end_time:   STUDY_END,
      break_frequency:  45,
      break_duration:   10,
      max_per_subject:  45
    ).schedule([prior, biology])

    timeline     = result[Date.current.to_s][:timeline]
    bio_slots    = timeline.select { |s| s[:type] == "study" && s[:label] == "Biology Research" }
    assert_equal 1, bio_slots.size,
      "Biology Research should appear as a single study block with the break deferred"
    assert_equal 36, bio_slots.first[:end_m] - bio_slots.first[:start_m]
  end
end
