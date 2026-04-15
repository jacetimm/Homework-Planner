require "test_helper"

class HiddenAssignmentsControllerTest < ActionDispatch::IntegrationTest
  include LoginHelper

  setup do
    @user = User.create!(
      email:         "hidden_ctrl@example.com",
      google_uid:    "uid_hidden_#{SecureRandom.hex(4)}",
      access_token:  "tok",
      refresh_token: "ref"
    )
  end

  # ── Auth guards ──────────────────────────────────────────────────────────

  test "create returns 401 for unauthenticated user" do
    post hidden_assignments_path, params: { course_work_id: "cw1" }
    assert_response :unauthorized
  end

  test "destroy returns 401 for unauthenticated user" do
    delete hidden_assignment_path(course_work_id: "cw1")
    assert_response :unauthorized
  end

  # ── create (hide) ────────────────────────────────────────────────────────

  test "create hides an assignment" do
    login_as(@user)
    assert_difference "HiddenAssignment.count", 1 do
      post hidden_assignments_path,
           params: { course_work_id: "cw_hide1", course_name: "Math", assignment_title: "Ch1 HW" }
    end
    ha = HiddenAssignment.find_by(course_work_id: "cw_hide1", user: @user)
    assert_not_nil ha
    assert_equal "Math", ha.course_name
    assert_equal "Ch1 HW", ha.assignment_title
  end

  test "create is idempotent — calling twice does not duplicate" do
    login_as(@user)
    2.times do
      post hidden_assignments_path,
           params: { course_work_id: "cw_idempotent", course_name: "Math", assignment_title: "Test" }
    end
    assert_equal 1, HiddenAssignment.where(course_work_id: "cw_idempotent", user: @user).count
  end

  test "create redirects to root on HTML format" do
    login_as(@user)
    post hidden_assignments_path,
         params: { course_work_id: "cw_html_hide", course_name: "Sci", assignment_title: "Lab" }
    assert_redirected_to root_path
  end

  # ── destroy (unhide) ─────────────────────────────────────────────────────

  test "destroy removes the hidden assignment record" do
    login_as(@user)
    ha = HiddenAssignment.create!(
      user: @user,
      course_work_id: "cw_unhide",
      hidden_at:      Time.current
    )
    assert_difference "HiddenAssignment.count", -1 do
      delete hidden_assignment_path(course_work_id: "cw_unhide")
    end
    assert_nil HiddenAssignment.find_by(id: ha.id)
  end

  test "destroy is a no-op when assignment was never hidden" do
    login_as(@user)
    assert_no_difference "HiddenAssignment.count" do
      delete hidden_assignment_path(course_work_id: "cw_never_hidden")
    end
    # Should not raise — silently succeeds
    assert_response :redirect
  end

  test "destroy cannot remove another user's hidden assignment" do
    other = User.create!(
      email: "other_hidden@example.com",
      google_uid: "uid_other_hidden_#{SecureRandom.hex(4)}",
      access_token: "tok",
      refresh_token: "ref"
    )
    HiddenAssignment.create!(user: other, course_work_id: "cw_others", hidden_at: Time.current)
    login_as(@user)
    assert_no_difference "HiddenAssignment.count" do
      delete hidden_assignment_path(course_work_id: "cw_others")
    end
    assert_not_nil HiddenAssignment.find_by(course_work_id: "cw_others", user: other)
  end
end
