require "test_helper"

class CrunchControllerTest < ActionDispatch::IntegrationTest
  include LoginHelper

  setup do
    @user = User.create!(
      email:         "crunch_ctrl@example.com",
      google_uid:    "uid_crunch_#{SecureRandom.hex(4)}",
      access_token:  "tok",
      refresh_token: "ref"
    )
  end

  # ── show ─────────────────────────────────────────────────────────────────

  test "show redirects unauthenticated user to google oauth" do
    get crunch_show_path(course_work_id: "cw1")
    assert_response :redirect
    assert_match %r{/auth/google_oauth2}, response.location
  end

  test "show redirects authenticated user to root with open_crunch param" do
    login_as(@user)
    get crunch_show_path(course_work_id: "cw_open")
    assert_redirected_to root_path(open_crunch: "cw_open")
  end

  # ── microtasks ───────────────────────────────────────────────────────────

  test "microtasks returns 401 when not logged in" do
    get crunch_microtasks_path(course_work_id: "cw1"), as: :json
    assert_response :unauthorized
  end

  test "microtasks returns 404 when estimate not found" do
    login_as(@user)
    get crunch_microtasks_path(course_work_id: "cw_missing"), as: :json
    assert_response :not_found
  end

  test "microtasks returns cached tasks when present" do
    login_as(@user)
    cached_tasks = [{ "task" => "Read chapter", "minutes" => 20 }]
    AssignmentEstimate.create!(
      course_work_id:    "cw_cached",
      user_email:        @user.email,
      estimated_minutes: 30,
      microtasks:        cached_tasks
    )
    get crunch_microtasks_path(course_work_id: "cw_cached"), as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["cached"]
    assert_equal cached_tasks, json["microtasks"]
  end

  test "microtasks generates and caches tasks when none exist" do
    login_as(@user)
    AssignmentEstimate.create!(
      course_work_id:    "cw_gen",
      user_email:        @user.email,
      estimated_minutes: 30,
      microtasks:        nil
    )
    generated = [{ "task" => "Step 1", "minutes" => 10 }, { "task" => "Step 2", "minutes" => 20 }]
    fake_gen = Object.new
    fake_gen.define_singleton_method(:generate) { |**| generated }
    MicrotaskGenerator.stub(:new, fake_gen) do
      get crunch_microtasks_path(course_work_id: "cw_gen"), as: :json
    end
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal false, json["cached"]
    assert_equal 2, json["microtasks"].length
    # Verify it was cached in DB
    assert_equal generated, AssignmentEstimate.find_by(course_work_id: "cw_gen", user_email: @user.email).microtasks
  end

  test "microtasks returns fallback tasks when generator returns nothing" do
    login_as(@user)
    AssignmentEstimate.create!(
      course_work_id:    "cw_fallback",
      user_email:        @user.email,
      estimated_minutes: 40,
      microtasks:        nil
    )
    fake_gen = Object.new
    fake_gen.define_singleton_method(:generate) { |**| [] }
    MicrotaskGenerator.stub(:new, fake_gen) do
      get crunch_microtasks_path(course_work_id: "cw_fallback"), as: :json
    end
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["fallback"]
    assert json["microtasks"].length >= 4
  end
end
