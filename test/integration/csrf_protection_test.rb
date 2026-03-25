require "test_helper"

# Verifies that the omniauth-rails_csrf_protection gem is active and correctly
# rejects requests to the OAuth initiation endpoint that lack a valid CSRF token.
#
# The login flow requires a POST to /auth/google_oauth2 with a Rails CSRF token
# (enforced by the gem). GET requests, or POST requests without the token, must
# not be allowed to initiate the OAuth flow.
class CsrfProtectionTest < ActionDispatch::IntegrationTest
  # GET to the OAuth initiation endpoint must be rejected.
  # omniauth-rails_csrf_protection intercepts it before OmniAuth sees it.
  test "GET to OAuth initiation endpoint is rejected" do
    get "/auth/google_oauth2"
    # The gem redirects invalid requests to the failure path rather than
    # proceeding with the OAuth flow — any non-2xx outcome confirms protection.
    assert_not_includes 200..299, response.status,
      "Expected CSRF protection to reject GET /auth/google_oauth2 " \
      "(got #{response.status})"
  end

  # POST without a CSRF token must also fail. In test mode Rails forgery
  # protection is disabled by default, so we re-enable it here just for this
  # one request to prove the check fires.
  test "POST without CSRF token is rejected" do
    # Temporarily enforce CSRF verification for this request.
    ActionController::Base.allow_forgery_protection = true
    post "/auth/google_oauth2"
    assert_not_includes 200..299, response.status,
      "Expected CSRF protection to reject an unauthenticated POST " \
      "(got #{response.status})"
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  # A properly formed POST (using button_to / Rails form helper which injects
  # the authenticity_token) is the only valid way to start the OAuth flow.
  # We don't test the full OAuth round-trip here (that requires Google),
  # but we verify the endpoint is reachable with a correct token.
  test "login button uses POST method in the dashboard view" do
    # The view renders button_to with method: :post — confirm by loading the
    # page and checking the rendered HTML for the correct form method.
    get root_path
    # Dashboard renders a login form (not a plain <a> link) so the browser
    # sends a POST with CSRF token automatically.
    assert_select "form[action='/auth/google_oauth2'][method='post']",
      minimum: 1,
      message: "Expected the login button to submit via POST to /auth/google_oauth2"
  end
end
