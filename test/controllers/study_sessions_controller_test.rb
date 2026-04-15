require "test_helper"

class StudySessionsControllerTest < ActionDispatch::IntegrationTest
  include LoginHelper

  setup do
    @user = User.create!(
      email:         "study_ctrl@example.com",
      google_uid:    "uid_study_#{SecureRandom.hex(4)}",
      access_token:  "tok",
      refresh_token: "ref"
    )
  end

  # ── Auth guards ──────────────────────────────────────────────────────────

  test "create returns 401 when not logged in" do
    post study_sessions_path,
         params: { study_session: { course_work_id: "cw1", assignment_title: "Test", course_name: "Math", estimated_minutes: 30 } },
         as: :json
    assert_response :unauthorized
  end

  test "update returns 401 when not logged in" do
    patch study_session_path(id: 999),
          params: { study_session: { actual_minutes: 30 } },
          as: :json
    assert_response :unauthorized
  end

  # ── create ───────────────────────────────────────────────────────────────

  test "create returns session id JSON and persists session" do
    login_as(@user)
    assert_difference "StudySession.count", 1 do
      post study_sessions_path,
           params: { study_session: { course_work_id: "cw_ss1", assignment_title: "Essay", course_name: "English", estimated_minutes: 45 } },
           as: :json
    end
    assert_response :success
    json = JSON.parse(response.body)
    assert json["id"].present?
    ss = StudySession.find(json["id"])
    assert_equal @user.email, ss.user_email
    assert_equal 45, ss.estimated_minutes
    assert_nil ss.actual_minutes
  end

  test "create records study day on user setting" do
    login_as(@user)
    setting = UserSetting.for_user(@user)
    assert_nil setting.streak_last_date

    post study_sessions_path,
         params: { study_session: { course_work_id: "cw_ss2", assignment_title: "Essay", course_name: "English", estimated_minutes: 30 } },
         as: :json
    assert_equal Date.current, setting.reload.streak_last_date
  end

  # ── update ───────────────────────────────────────────────────────────────

  test "update saves actual_minutes and returns json" do
    login_as(@user)
    ss = StudySession.create!(
      course_work_id:    "cw_upd",
      user_email:        @user.email,
      assignment_title:  "Calc HW",
      course_name:       "Math",
      estimated_minutes: 30,
      user_id:           @user.id,
      started_at:        Time.current
    )
    patch study_session_path(id: ss.id),
          params: { study_session: { actual_minutes: 42 } },
          as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true,  json["ok"]
    assert_equal 42,    json["actual_minutes"]
    assert_equal 42,    ss.reload.actual_minutes
  end

  test "update returns 404 for session owned by another user" do
    other = User.create!(
      email: "other_study@example.com",
      google_uid: "uid_other_study_#{SecureRandom.hex(4)}",
      access_token: "tok",
      refresh_token: "ref"
    )
    ss = StudySession.create!(
      course_work_id:    "cw_other",
      user_email:        other.email,
      assignment_title:  "Test",
      course_name:       "Science",
      estimated_minutes: 20,
      user_id:           other.id,
      started_at:        Time.current
    )
    login_as(@user)
    patch study_session_path(id: ss.id),
          params: { study_session: { actual_minutes: 10 } },
          as: :json
    assert_response :not_found
  end

  test "update floors zero actual_minutes to 1" do
    login_as(@user)
    ss = StudySession.create!(
      course_work_id:    "cw_floor",
      user_email:        @user.email,
      assignment_title:  "Test",
      course_name:       "Math",
      estimated_minutes: 30,
      user_id:           @user.id,
      started_at:        Time.current
    )
    patch study_session_path(id: ss.id),
          params: { study_session: { actual_minutes: 0 } },
          as: :json
    assert_equal 1, ss.reload.actual_minutes
  end
end
