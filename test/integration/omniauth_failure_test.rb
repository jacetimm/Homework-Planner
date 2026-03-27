require "test_helper"

class OmniAuthFailureTest < ActionDispatch::IntegrationTest
  test "invalid_client redirects with a configuration-specific alert" do
    get "/auth/failure", params: { message: "invalid_client" }

    assert_redirected_to root_path
    follow_redirect!
    assert_match(/Google OAuth is misconfigured/i, flash[:alert].to_s)
  end

  test "unknown failures keep the generic alert" do
    get "/auth/failure", params: { message: "access_denied" }

    assert_redirected_to root_path
    follow_redirect!
    assert_equal "Authentication failed.", flash[:alert]
  end
end
