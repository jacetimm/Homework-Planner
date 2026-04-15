require "test_helper"

class UserSettingTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user = User.create!(
      email:         "us_model@example.com",
      google_uid:    "uid_us_#{SecureRandom.hex(4)}",
      access_token:  "tok",
      refresh_token: "ref"
    )
    @setting = UserSetting.for_user(@user)
  end

  # ── for_user ─────────────────────────────────────────────────────────────

  test "for_user creates a setting on first call" do
    assert_not_nil @setting
    assert_equal @user.id, @setting.user_id
  end

  test "for_user returns the same record on subsequent calls" do
    second = UserSetting.for_user(@user)
    assert_equal @setting.id, second.id
  end

  # ── record_study_day! ─────────────────────────────────────────────────────

  test "record_study_day! sets streak_last_date to today on first call" do
    travel_to Time.zone.local(2026, 4, 14) do
      @setting.record_study_day!
      assert_equal Date.new(2026, 4, 14), @setting.reload.streak_last_date
    end
  end

  test "record_study_day! starts a streak on first call" do
    travel_to Time.zone.local(2026, 4, 14) do
      @setting.record_study_day!
      assert_equal 1, @setting.reload.streak_count
    end
  end

  test "record_study_day! increments streak on consecutive day" do
    travel_to Time.zone.local(2026, 4, 13) do
      @setting.record_study_day!
    end
    travel_to Time.zone.local(2026, 4, 14) do
      @setting.record_study_day!
      assert_equal 2, @setting.reload.streak_count
    end
  end

  test "record_study_day! resets streak after a gap day" do
    travel_to Time.zone.local(2026, 4, 12) do
      @setting.record_study_day!
    end
    travel_to Time.zone.local(2026, 4, 14) do
      @setting.record_study_day!
      assert_equal 1, @setting.reload.streak_count
    end
  end

  test "record_study_day! does not increment streak twice on same day" do
    travel_to Time.zone.local(2026, 4, 14) do
      @setting.record_study_day!
      @setting.record_study_day!
      assert_equal 1, @setting.reload.streak_count
    end
  end

  # ── streak_active? ───────────────────────────────────────────────────────

  test "streak_active? is true when last_visit_date is today" do
    travel_to Time.zone.local(2026, 4, 14) do
      @setting.update!(streak_last_date: Date.current, streak_count: 3)
      assert @setting.streak_active?
    end
  end

  test "streak_active? is true when last_visit_date is yesterday" do
    travel_to Time.zone.local(2026, 4, 14) do
      @setting.update!(streak_last_date: Date.yesterday, streak_count: 2)
      assert @setting.streak_active?
    end
  end

  test "streak_active? is false when last_visit_date is two days ago" do
    travel_to Time.zone.local(2026, 4, 14) do
      @setting.update!(streak_last_date: Date.new(2026, 4, 12), streak_count: 5)
      refute @setting.streak_active?
    end
  end
end
