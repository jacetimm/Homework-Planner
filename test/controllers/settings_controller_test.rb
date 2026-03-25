require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "redirects to root when not logged in" do
    get settings_path
    assert_redirected_to root_path
  end
end
