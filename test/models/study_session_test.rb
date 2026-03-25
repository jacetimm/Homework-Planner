require "test_helper"

class StudySessionTest < ActiveSupport::TestCase
  EMAIL = "calibration_student@example.com"

  def make_session(course_name: "Math", estimated_minutes:, actual_minutes:)
    StudySession.create!(
      course_work_id:    SecureRandom.hex(4),
      user_email:        EMAIL,
      assignment_title:  "Test Assignment",
      course_name:       course_name,
      estimated_minutes: estimated_minutes,
      actual_minutes:    actual_minutes
    )
  end

  # ── calibration_factors ──────────────────────────────────────────────────

  test "factor is computed as actual / estimated ratio" do
    3.times { make_session(estimated_minutes: 30, actual_minutes: 45) }
    factors = StudySession.calibration_factors(EMAIL)
    assert_in_delta 1.5, factors["Math"], 0.05
  end

  test "factor above 1.1 is included in results" do
    # 34/30 ≈ 1.13 > 1.1 → included
    3.times { make_session(estimated_minutes: 30, actual_minutes: 34) }
    factors = StudySession.calibration_factors(EMAIL)
    assert factors.key?("Math")
  end

  test "factor at or below 1.1 is excluded (fast or on-pace student)" do
    # 30/30 = 1.0 — student is on pace, no upward adjustment
    3.times { make_session(estimated_minutes: 30, actual_minutes: 30) }
    factors = StudySession.calibration_factors(EMAIL)
    refute factors.key?("Math")
  end

  test "fewer than 3 completed sessions yields no calibration" do
    2.times { make_session(estimated_minutes: 30, actual_minutes: 60) }
    assert_empty StudySession.calibration_factors(EMAIL)
  end

  test "min_sessions threshold is configurable" do
    2.times { make_session(estimated_minutes: 30, actual_minutes: 60) }
    factors = StudySession.calibration_factors(EMAIL, min_sessions: 2)
    assert factors.key?("Math")
  end

  test "only courses with enough sessions are included" do
    3.times { make_session(course_name: "Math",    estimated_minutes: 30, actual_minutes: 60) }
    2.times { make_session(course_name: "English", estimated_minutes: 30, actual_minutes: 60) }

    factors = StudySession.calibration_factors(EMAIL)
    assert  factors.key?("Math")
    refute  factors.key?("English")
  end

  test "calibration is scoped per user email" do
    3.times { make_session(estimated_minutes: 30, actual_minutes: 60) }
    assert_empty StudySession.calibration_factors("other_student@example.com")
  end

  test "sessions without actual_minutes are excluded from calibration" do
    # 3 incomplete sessions + 0 complete → no calibration
    3.times do
      StudySession.create!(
        course_work_id:    SecureRandom.hex(4),
        user_email:        EMAIL,
        assignment_title:  "Test",
        course_name:       "Math",
        estimated_minutes: 30,
        actual_minutes:    nil
      )
    end
    assert_empty StudySession.calibration_factors(EMAIL)
  end
end
