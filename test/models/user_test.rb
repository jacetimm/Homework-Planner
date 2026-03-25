require "test_helper"
require "ostruct"

class UserTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email:         "test_user@example.com",
      google_uid:    "uid_user_test_#{SecureRandom.hex(4)}",
      name:          "Test User",
      access_token:  "original_access_token",
      refresh_token: "original_refresh_token"
    )
  end

  # ── backfill_email_records! ───────────────────────────────────────────────

  test "links unowned assignment_estimates to the user by email" do
    est = AssignmentEstimate.create!(
      user_email:        @user.email,
      course_work_id:    "cw_backfill_est",
      estimated_minutes: 30
    )
    assert_nil est.user_id

    @user.backfill_email_records!

    assert_equal @user.id, est.reload.user_id
  end

  test "links unowned study_sessions to the user by email" do
    ss = StudySession.create!(
      user_email:       @user.email,
      course_work_id:   "cw_backfill_ss",
      assignment_title: "Test Assignment"
    )
    assert_nil ss.user_id

    @user.backfill_email_records!

    assert_equal @user.id, ss.reload.user_id
  end

  test "does not overwrite records already owned by another user" do
    other = User.create!(
      email:        "other@example.com",
      google_uid:   "uid_other_#{SecureRandom.hex(4)}",
      access_token: "tok",
      refresh_token: "ref"
    )
    est = AssignmentEstimate.create!(
      user_email:        other.email,
      course_work_id:    "cw_other_est",
      estimated_minutes: 30,
      user_id:           other.id
    )

    @user.backfill_email_records!

    assert_equal other.id, est.reload.user_id
  end

  test "backfill is a no-op when no matching orphaned records exist" do
    assert_nothing_raised { @user.backfill_email_records! }
  end

  # ── refresh_access_token! ────────────────────────────────────────────────

  test "updates access_token in the database and returns the new token" do
    expires_ts    = Time.now.to_i + 3600
    new_token_obj = OpenStruct.new(
      token:         "refreshed_access_token",
      refresh_token: nil,   # server didn't rotate the refresh token
      expires_at:    expires_ts
    )

    fake_bearer = Object.new
    fake_bearer.define_singleton_method(:refresh!) { new_token_obj }

    OAuth2::Client.stub(:new, :irrelevant_client) do
      OAuth2::AccessToken.stub(:new, fake_bearer) do
        returned = @user.refresh_access_token!

        assert_equal "refreshed_access_token", returned
        assert_equal "refreshed_access_token", @user.reload.access_token
      end
    end
  end

  test "preserves original refresh_token when server does not rotate it" do
    new_token_obj = OpenStruct.new(
      token:         "new_token",
      refresh_token: nil,
      expires_at:    Time.now.to_i + 3600
    )
    fake_bearer = Object.new
    fake_bearer.define_singleton_method(:refresh!) { new_token_obj }

    OAuth2::Client.stub(:new, :irrelevant_client) do
      OAuth2::AccessToken.stub(:new, fake_bearer) do
        @user.refresh_access_token!
        assert_equal "original_refresh_token", @user.reload.refresh_token
      end
    end
  end

  test "stores new refresh_token when server rotates it" do
    new_token_obj = OpenStruct.new(
      token:         "new_token",
      refresh_token: "rotated_refresh_token",
      expires_at:    Time.now.to_i + 3600
    )
    fake_bearer = Object.new
    fake_bearer.define_singleton_method(:refresh!) { new_token_obj }

    OAuth2::Client.stub(:new, :irrelevant_client) do
      OAuth2::AccessToken.stub(:new, fake_bearer) do
        @user.refresh_access_token!
        assert_equal "rotated_refresh_token", @user.reload.refresh_token
      end
    end
  end

  test "updates token_expires_at from the server response" do
    future_ts = Time.now.to_i + 7200
    new_token_obj = OpenStruct.new(
      token:         "new_token",
      refresh_token: nil,
      expires_at:    future_ts
    )
    fake_bearer = Object.new
    fake_bearer.define_singleton_method(:refresh!) { new_token_obj }

    OAuth2::Client.stub(:new, :irrelevant_client) do
      OAuth2::AccessToken.stub(:new, fake_bearer) do
        @user.refresh_access_token!
        assert_in_delta Time.at(future_ts).to_i, @user.reload.token_expires_at.to_i, 2
      end
    end
  end
end
