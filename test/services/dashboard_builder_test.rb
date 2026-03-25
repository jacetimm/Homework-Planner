require "test_helper"
require "ostruct"

class DashboardBuilderTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  FROZEN_AT = Time.zone.local(2026, 3, 24, 10, 0, 0)

  setup do
    travel_to FROZEN_AT

    @user = User.create!(
      email:        "dash_builder_student@example.com",
      google_uid:   "uid_dash_#{SecureRandom.hex(4)}",
      access_token: "test_access_token",
      refresh_token: "test_refresh_token"
    )

    # Ensure UserSetting exists with known values; skip calendar to avoid
    # needing a CalendarService stub in most tests.
    @setting = UserSetting.for_user(@user)
    @setting.update!(
      study_start_time:             Time.parse("19:00:00"),
      study_end_time:               Time.parse("22:00:00"),
      break_frequency:              45,
      break_duration:               10,
      block_google_calendar_events: false
    )
  end

  teardown { travel_back }

  # ── Helpers ───────────────────────────────────────────────────────────────

  def fake_classroom(courses: [], assignments: [])
    OpenStruct.new(courses: courses, assignments: assignments)
  end

  def run_builder(classroom:)
    ClassroomService.stub(:new, classroom) do
      DashboardBuilder.new(@user).call
    end
  end

  # ── Result shape ──────────────────────────────────────────────────────────

  test "result exposes all 9 expected fields" do
    result = run_builder(classroom: fake_classroom)

    %i[courses schedule tonight_assignments tonight_summary
       weekly_preview danger_zone danger_zone_ids streak calibration_nudges].each do |field|
      assert_respond_to result, field, "Result missing field: #{field}"
    end
  end

  # ── Empty / new user ──────────────────────────────────────────────────────

  test "handles a new user with no classroom assignments" do
    result = run_builder(classroom: fake_classroom)

    assert_empty result.courses
    assert_empty result.tonight_assignments
    assert_empty result.danger_zone
    assert_empty result.calibration_nudges
    assert_equal 0, result.tonight_summary[:assignment_count]
    assert_equal 0, result.tonight_summary[:total_minutes]
  end

  test "weekly_preview totals are zero when there are no assignments" do
    result = run_builder(classroom: fake_classroom)
    assert_equal 0, result.weekly_preview[:total_assignments]
  end

  test "streak is read from the user setting" do
    @setting.update_columns(streak_count: 5, streak_last_date: Date.current)
    result = run_builder(classroom: fake_classroom)
    assert_equal 5, result.streak[:count]
    assert_equal true, result.streak[:active]
  end

  # ── With assignments ──────────────────────────────────────────────────────

  test "returns scheduled assignments when classroom has work" do
    # Pre-seed the estimate so EstimateAssignmentsJob is never triggered
    AssignmentEstimate.create!(
      user_email:        @user.email,
      course_work_id:    "cw_dash_1",
      estimated_minutes: 30
    )

    assignment = {
      course_work_id:     "cw_dash_1",
      title:              "Chapter 5 Reading",
      class_name:         "Biology",
      estimated_minutes:  30,
      due_date:           Date.current + 2,
      state:              nil,
      assignment_link:    nil,
      materials_metadata: []
    }

    result = run_builder(classroom: fake_classroom(assignments: [assignment]))

    assert_operator result.tonight_assignments.size, :>=, 1
    assert_operator result.tonight_summary[:assignment_count], :>=, 1
  end

  # ── Calendar error resilience ─────────────────────────────────────────────

  test "a calendar API error does not crash the builder" do
    @setting.update!(block_google_calendar_events: true)

    AssignmentEstimate.create!(
      user_email:        @user.email,
      course_work_id:    "cw_cal_err",
      estimated_minutes: 45
    )

    assignment = {
      course_work_id:     "cw_cal_err",
      title:              "Lab Report",
      class_name:         "Chemistry",
      estimated_minutes:  45,
      due_date:           Date.current + 1,
      state:              nil,
      assignment_link:    nil,
      materials_metadata: []
    }

    broken_calendar = Object.new
    broken_calendar.define_singleton_method(:busy_blocks_between) do |**|
      raise StandardError, "Calendar API is down"
    end

    ClassroomService.stub(:new, fake_classroom(assignments: [assignment])) do
      CalendarService.stub(:new, broken_calendar) do
        result = DashboardBuilder.new(@user).call
        # Should return a valid result, not raise
        assert_respond_to result, :schedule
        assert_respond_to result, :tonight_assignments
      end
    end
  end

  # ── Calibration integration ───────────────────────────────────────────────

  test "calibration_nudges is empty when no study sessions exist" do
    result = run_builder(classroom: fake_classroom)
    assert_empty result.calibration_nudges
  end

  test "calibration_nudges flags courses where factor is at the cap" do
    # cap is 3.0 — create sessions that produce a factor >= 3.0
    3.times do
      StudySession.create!(
        user_email:        @user.email,
        course_work_id:    SecureRandom.hex(4),
        assignment_title:  "Test",
        course_name:       "AP History",
        estimated_minutes: 10,
        actual_minutes:    35   # ratio = 3.5 > 3.0 cap → nudge triggered
      )
    end

    AssignmentEstimate.create!(
      user_email:        @user.email,
      course_work_id:    "cw_hist",
      estimated_minutes: 30
    )

    assignment = {
      course_work_id:     "cw_hist",
      title:              "Essay",
      class_name:         "AP History",
      estimated_minutes:  30,
      due_date:           Date.current + 3,
      state:              nil,
      assignment_link:    nil,
      materials_metadata: []
    }

    result = run_builder(classroom: fake_classroom(assignments: [assignment]))
    nudged_courses = result.calibration_nudges.map { |n| n[:course] }
    assert_includes nudged_courses, "AP History"
  end
end
