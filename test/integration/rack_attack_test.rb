require "test_helper"

# Tests that Rack::Attack throttles fire at the right thresholds.
#
# Two test-environment concerns to work around:
#   1. The localhost safelist bypasses all throttles for 127.0.0.1 / ::1.
#      We send requests with REMOTE_ADDR set to a fake external IP.
#   2. The default test cache store is :null_store (counts nothing).
#      We give Rack::Attack its own MemoryStore and reset it between tests.
class RackAttackTest < ActionDispatch::IntegrationTest
  EXTERNAL_IP = "203.0.113.42"   # TEST-NET-3; never a real user's IP
  ENV_OVERRIDES = { "REMOTE_ADDR" => EXTERNAL_IP }.freeze

  MOCK_AUTH = OmniAuth::AuthHash.new(
    uid:         "throttle_test_uid",
    info:        { email: "throttle@example.com", name: "Throttle Test", image: nil },
    credentials: { token: "fake_token", refresh_token: "fake_refresh", expires_at: nil }
  )

  setup do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    OmniAuth.config.mock_auth[:google_oauth2] = MOCK_AUTH
  end

  teardown do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    OmniAuth.config.mock_auth.delete(:google_oauth2)
  end

  # ── General IP throttle (60 req/min) ─────────────────────────────────────

  test "allows requests under the general limit" do
    get root_path, env: ENV_OVERRIDES
    assert_not_equal 429, response.status
  end

  test "blocks requests over 60 per minute for the same IP" do
    60.times { get root_path, env: ENV_OVERRIDES }
    get root_path, env: ENV_OVERRIDES
    assert_equal 429, response.status
  end

  test "429 response includes Retry-After header" do
    60.times { get root_path, env: ENV_OVERRIDES }
    get root_path, env: ENV_OVERRIDES
    assert response.headers["Retry-After"].present?
  end

  test "429 body contains a human-readable message" do
    60.times { get root_path, env: ENV_OVERRIDES }
    get root_path, env: ENV_OVERRIDES
    assert_match(/slow down/i, response.body)
  end

  # ── Login throttle (5 per minute) ────────────────────────────────────────

  test "allows up to 5 OAuth callback attempts per minute" do
    5.times { get "/auth/google_oauth2/callback", env: ENV_OVERRIDES }
    assert_not_equal 429, response.status
  end

  test "blocks the 6th OAuth callback attempt within a minute" do
    6.times { get "/auth/google_oauth2/callback", env: ENV_OVERRIDES }
    assert_equal 429, response.status
  end

  # ── Different IPs are tracked independently ───────────────────────────────

  test "throttle on one IP does not affect a different IP" do
    ip_a_env = { "REMOTE_ADDR" => "203.0.113.10" }
    ip_b_env = { "REMOTE_ADDR" => "203.0.113.20" }

    60.times { get root_path, env: ip_a_env }
    get root_path, env: ip_a_env
    assert_equal 429, response.status, "IP A should be throttled"

    get root_path, env: ip_b_env
    assert_not_equal 429, response.status, "IP B should still be allowed"
  end
end
