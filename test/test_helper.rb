ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "ostruct"

# Enable OmniAuth test mode so the callback route accepts our mock hash
# without performing real OAuth (no CSRF check in test mode).
OmniAuth.config.test_mode = true

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

# Shared helper for controller integration tests that need an authenticated session.
# OmniAuth.config.test_mode = true is set above, so we use the mock_auth API.
module LoginHelper
  # Log in as the given user via OmniAuth test mode.
  def login_as(user)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      uid:         user.google_uid,
      info:        { email: user.email, name: user.name.to_s, image: nil },
      credentials: { token: user.access_token, refresh_token: user.refresh_token, expires_at: nil }
    )
    get "/auth/google_oauth2/callback"
    follow_redirect! if response.redirect?
  end
end
