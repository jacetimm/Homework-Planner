require "test_helper"

class AssignmentsControllerTest < ActionDispatch::IntegrationTest
  include LoginHelper

  setup do
    @user = User.create!(
      email:         "assign_ctrl@example.com",
      google_uid:    "uid_assign_#{SecureRandom.hex(4)}",
      access_token:  "tok",
      refresh_token: "ref"
    )
  end

  # ── Auth guards ──────────────────────────────────────────────────────────

  test "reestimate redirects unauthenticated user to root" do
    post reestimate_assignment_path(course_work_id: "cw1")
    assert_redirected_to root_path
  end

  test "set_estimate redirects unauthenticated user to root" do
    post set_assignment_estimate_path(course_work_id: "cw1"), params: { minutes: "30" }
    assert_redirected_to root_path
  end

  # ── set_estimate ─────────────────────────────────────────────────────────

  test "set_estimate creates a new estimate for a valid integer minutes value" do
    login_as(@user)
    assert_difference "AssignmentEstimate.count", 1 do
      post set_assignment_estimate_path(course_work_id: "cw_new"),
           params: { minutes: "45" }
    end
    est = AssignmentEstimate.find_by(course_work_id: "cw_new", user_email: @user.email)
    assert_equal 45, est.estimated_minutes
  end

  test "set_estimate parses h/m duration string" do
    login_as(@user)
    post set_assignment_estimate_path(course_work_id: "cw_hm"),
         params: { minutes: "1h 30m" }
    est = AssignmentEstimate.find_by(course_work_id: "cw_hm", user_email: @user.email)
    assert_equal 90, est.estimated_minutes
  end

  test "set_estimate parses hh:mm colon format" do
    login_as(@user)
    post set_assignment_estimate_path(course_work_id: "cw_colon"),
         params: { minutes: "2:15" }
    est = AssignmentEstimate.find_by(course_work_id: "cw_colon", user_email: @user.email)
    assert_equal 135, est.estimated_minutes
  end

  test "set_estimate rejects zero minutes and sets flash alert" do
    login_as(@user)
    assert_no_difference "AssignmentEstimate.count" do
      post set_assignment_estimate_path(course_work_id: "cw_bad"),
           params: { minutes: "0" }
    end
    assert_not_nil flash[:alert]
  end

  test "set_estimate rejects values above 600 and sets flash alert" do
    login_as(@user)
    assert_no_difference "AssignmentEstimate.count" do
      post set_assignment_estimate_path(course_work_id: "cw_huge"),
           params: { minutes: "601" }
    end
    assert_not_nil flash[:alert]
  end

  test "set_estimate upserts existing estimate" do
    login_as(@user)
    AssignmentEstimate.create!(
      course_work_id:    "cw_upsert",
      user_email:        @user.email,
      estimated_minutes: 30
    )
    post set_assignment_estimate_path(course_work_id: "cw_upsert"),
         params: { minutes: "60" }
    assert_equal 60, AssignmentEstimate.find_by(course_work_id: "cw_upsert", user_email: @user.email).estimated_minutes
  end

  # ── reestimate ───────────────────────────────────────────────────────────

  test "reestimate creates reestimate record and clears cached estimate" do
    login_as(@user)
    AssignmentEstimate.create!(
      course_work_id:    "cw_re1",
      user_email:        @user.email,
      estimated_minutes: 30
    )
    assert_difference "AssignmentReestimate.count", 1 do
      post reestimate_assignment_path(course_work_id: "cw_re1")
    end
    assert_nil AssignmentEstimate.find_by(course_work_id: "cw_re1", user_email: @user.email)
    assert_not_nil flash[:notice]
  end

  test "reestimate blocks when per-assignment limit is hit" do
    login_as(@user)
    AssignmentReestimate::ASSIGNMENT_LIMIT.times do
      AssignmentReestimate.create!(course_work_id: "cw_limit", user_email: @user.email)
    end
    assert_no_difference "AssignmentReestimate.count" do
      post reestimate_assignment_path(course_work_id: "cw_limit")
    end
    assert_not_nil flash[:alert]
  end

  test "reestimate blocks when daily limit is hit" do
    login_as(@user)
    AssignmentReestimate::DAILY_LIMIT.times do |i|
      AssignmentReestimate.create!(course_work_id: "cw_daily_#{i}", user_email: @user.email)
    end
    assert_no_difference "AssignmentReestimate.count" do
      post reestimate_assignment_path(course_work_id: "cw_new_daily")
    end
    assert_not_nil flash[:alert]
  end
end
