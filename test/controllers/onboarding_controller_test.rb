require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  include LoginHelper

  setup do
    @user = User.create!(
      email:         "onboard_ctrl@example.com",
      google_uid:    "uid_onboard_#{SecureRandom.hex(4)}",
      access_token:  "tok",
      refresh_token: "ref"
    )
  end

  test "complete returns 401 when not logged in" do
    post complete_onboarding_path
    assert_response :unauthorized
  end

  test "complete saves study times and marks onboarding done" do
    login_as(@user)
    post complete_onboarding_path, params: {
      study_start_time: "17:00",
      study_end_time:   "22:00",
      color_theme:      "dark"
    }
    assert_response :ok
    setting = UserSetting.for_user(@user)
    assert setting.onboarding_completed
    assert_equal "dark", setting.color_theme
  end

  test "complete saves break frequency within valid range" do
    login_as(@user)
    post complete_onboarding_path, params: { break_frequency: "30", break_duration: "5" }
    assert_response :ok
    setting = UserSetting.for_user(@user)
    assert_equal 30, setting.break_frequency
    assert_equal 5, setting.break_duration
  end

  test "complete ignores break_frequency out of range" do
    login_as(@user)
    setting = UserSetting.for_user(@user)
    original = setting.break_frequency

    post complete_onboarding_path, params: { break_frequency: "999" }
    assert_response :ok
    assert_equal original, setting.reload.break_frequency
  end

  test "complete ignores invalid color_theme" do
    login_as(@user)
    setting = UserSetting.for_user(@user)
    original = setting.color_theme

    post complete_onboarding_path, params: { color_theme: "rainbow" }
    assert_response :ok
    assert_equal original, setting.reload.color_theme
  end

  test "complete saves hard subjects array" do
    login_as(@user)
    post complete_onboarding_path, params: {
      hard_subjects: ["Math", "Physics", ""]
    }
    assert_response :ok
    setting = UserSetting.for_user(@user)
    assert_includes setting.hard_subjects, "Math"
    assert_includes setting.hard_subjects, "Physics"
    refute_includes setting.hard_subjects, ""
  end

  test "complete saves max_minutes_per_subject within valid range" do
    login_as(@user)
    post complete_onboarding_path, params: { max_minutes_per_subject: "60" }
    assert_response :ok
    assert_equal 60, UserSetting.for_user(@user).max_minutes_per_subject
  end

  test "complete ignores max_minutes_per_subject out of range" do
    login_as(@user)
    setting = UserSetting.for_user(@user)
    original = setting.max_minutes_per_subject

    post complete_onboarding_path, params: { max_minutes_per_subject: "500" }
    assert_response :ok
    assert_equal original, setting.reload.max_minutes_per_subject
  end
end
