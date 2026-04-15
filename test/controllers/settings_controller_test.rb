require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  include LoginHelper

  setup do
    @user = User.create!(
      email:         "settings_ctrl@example.com",
      google_uid:    "uid_settings_#{SecureRandom.hex(4)}",
      access_token:  "tok",
      refresh_token: "ref"
    )
  end

  def stub_external_services(calendars = [])
    fake_cal = Object.new
    fake_cal.define_singleton_method(:calendars) { calendars }
    fake_cs = Object.new
    fake_cs.define_singleton_method(:courses) { [] }
    CalendarService.stub(:new, fake_cal) do
      ClassroomService.stub(:new, fake_cs) do
        yield
      end
    end
  end

  # kept as alias so existing test calls work
  alias stub_calendars stub_external_services

  # ── Auth guard ───────────────────────────────────────────────────────────

  test "redirects to root when not logged in" do
    get settings_path
    assert_redirected_to root_path
  end

  # ── show ─────────────────────────────────────────────────────────────────

  test "show renders successfully for logged-in user" do
    login_as(@user)
    stub_external_services do
      get settings_path
      assert_response :success
    end
  end

  # ── update ───────────────────────────────────────────────────────────────

  test "update saves study times and redirects with notice" do
    login_as(@user)
    stub_calendars do
      patch settings_path, params: {
        user_setting: {
          study_start_time: "18:00",
          study_end_time:   "22:00",
          break_frequency:  45,
          break_duration:   10,
          color_theme:      "light",
          hard_subjects:    ["", "Math"],
          extracurricular_blocks: {}
        }
      }
      assert_redirected_to settings_path
      follow_redirect!
    end
    assert_not_nil flash[:notice]
    setting = UserSetting.for_user(@user)
    assert_equal "light", setting.color_theme
    assert_includes setting.hard_subjects, "Math"
    refute_includes setting.hard_subjects, ""
  end

  test "update derives ignored_google_calendar_ids from included set" do
    login_as(@user)
    all_cals = [
      { id: "cal_a", summary: "Personal", primary: true,  selected: true },
      { id: "cal_b", summary: "Work",     primary: false, selected: true }
    ]
    fake_cal = Object.new
    fake_cal.define_singleton_method(:calendars) { all_cals }
    CalendarService.stub(:new, fake_cal) do
      patch settings_path, params: {
        user_setting: {
          included_google_calendar_ids: ["cal_a"],
          study_start_time:  "18:00",
          study_end_time:    "22:00",
          break_frequency:   45,
          break_duration:    10,
          hard_subjects:     [],
          extracurricular_blocks: {}
        }
      }
    end
    setting = UserSetting.for_user(@user)
    assert_includes setting.ignored_google_calendar_ids, "cal_b"
    refute_includes setting.ignored_google_calendar_ids, "cal_a"
  end

  test "update strips blank hard_subjects" do
    login_as(@user)
    stub_calendars do
      patch settings_path, params: {
        user_setting: {
          hard_subjects: ["", "Chemistry", ""],
          study_start_time:  "18:00",
          study_end_time:    "22:00",
          break_frequency:   45,
          break_duration:    10,
          extracurricular_blocks: {}
        }
      }
    end
    assert_equal ["Chemistry"], UserSetting.for_user(@user).hard_subjects
  end

  test "update saves calendar ignore rules" do
    login_as(@user)
    stub_calendars do
      patch settings_path, params: {
        user_setting: {
          calendar_ignore_rules: {
            "0" => { keyword: "lunch", calendar_id: "" }
          },
          study_start_time:  "18:00",
          study_end_time:    "22:00",
          break_frequency:   45,
          break_duration:    10,
          hard_subjects:     [],
          extracurricular_blocks: {}
        }
      }
    end
    rules = UserSetting.for_user(@user).calendar_ignore_rules
    assert rules.any? { |r| r["keyword"] == "lunch" }
  end

  test "update saves extracurricular blocks" do
    login_as(@user)
    stub_calendars do
      patch settings_path, params: {
        user_setting: {
          extracurricular_blocks: {
            "0" => { activity: "Soccer", start_time: "15:00", end_time: "17:00", days: "Mon,Wed" }
          },
          study_start_time:  "18:00",
          study_end_time:    "22:00",
          break_frequency:   45,
          break_duration:    10,
          hard_subjects:     []
        }
      }
    end
    blocks = UserSetting.for_user(@user).extracurricular_blocks
    assert_equal 1, blocks.length
    assert_equal "Soccer", blocks.first["activity"]
  end

  test "update skips extracurricular blocks with blank activity" do
    login_as(@user)
    stub_calendars do
      patch settings_path, params: {
        user_setting: {
          extracurricular_blocks: {
            "0" => { activity: "", start_time: "15:00", end_time: "17:00", days: "Mon" }
          },
          study_start_time:  "18:00",
          study_end_time:    "22:00",
          break_frequency:   45,
          break_duration:    10,
          hard_subjects:     []
        }
      }
    end
    assert_empty UserSetting.for_user(@user).extracurricular_blocks
  end
end
