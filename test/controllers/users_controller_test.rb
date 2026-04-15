require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  include LoginHelper

  setup do
    @user = User.create!(
      email:         "tz_ctrl@example.com",
      google_uid:    "uid_tz_#{SecureRandom.hex(4)}",
      access_token:  "tok",
      refresh_token: "ref"
    )
  end

  test "set_timezone returns 401 when not logged in" do
    patch set_user_timezone_path, params: { timezone: "America/Chicago" }
    assert_response :unauthorized
  end

  test "set_timezone saves valid IANA timezone and returns 200" do
    login_as(@user)
    patch set_user_timezone_path, params: { timezone: "America/Chicago" }
    assert_response :ok
    assert_not_nil @user.reload.timezone
    # Should be stored as ActiveSupport zone name, not raw IANA
    assert_equal "Central Time (US & Canada)", @user.reload.timezone
  end

  test "set_timezone returns 422 for unknown timezone" do
    login_as(@user)
    patch set_user_timezone_path, params: { timezone: "Fake/Zone" }
    assert_response :unprocessable_entity
  end

  test "set_timezone handles common US timezones" do
    login_as(@user)
    {
      "America/New_York"    => "Eastern Time (US & Canada)",
      "America/Los_Angeles" => "Pacific Time (US & Canada)",
      "America/Denver"      => "Mountain Time (US & Canada)"
    }.each do |iana, expected|
      patch set_user_timezone_path, params: { timezone: iana }
      assert_response :ok
      assert_equal expected, @user.reload.timezone
    end
  end
end
