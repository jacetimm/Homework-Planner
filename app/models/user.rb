require "oauth2"

class User < ApplicationRecord
  encrypts :access_token
  encrypts :refresh_token

  has_one  :user_setting,           dependent: :destroy
  has_many :assignment_estimates,   dependent: :destroy
  has_many :study_sessions,         dependent: :destroy
  has_many :assignment_reestimates, dependent: :destroy
  has_many :assignment_alerts,      dependent: :destroy
  has_one  :classroom_cache,        dependent: :destroy
  has_one  :calendar_cache,         dependent: :destroy

  validates :email,      presence: true, uniqueness: true
  validates :google_uid, presence: true, uniqueness: true

  # Refresh the stored access token using the stored refresh token.
  # Updates the record in-place and returns the new token string.
  # Called by ApplicationController#reauthenticate and background jobs.
  def refresh_access_token!
    client = OAuth2::Client.new(
      Rails.application.credentials.dig(:google, :client_id),
      Rails.application.credentials.dig(:google, :client_secret),
      site: "https://oauth2.googleapis.com",
      token_url: "/token"
    )
    bearer = OAuth2::AccessToken.new(client, access_token, refresh_token: refresh_token)
    new_token = bearer.refresh!

    update!(
      access_token:     new_token.token,
      refresh_token:    new_token.refresh_token.presence || refresh_token,
      token_expires_at: new_token.expires_at ? Time.at(new_token.expires_at) : nil
    )
    new_token.token
  end

  # On first login with a new User record, wire up any pre-existing rows that
  # were keyed by email string before the users table existed.
  def backfill_email_records!
    e = email
    UserSetting.where(user_email: e, user_id: nil).update_all(user_id: id)
    AssignmentEstimate.where(user_email: e, user_id: nil).update_all(user_id: id)
    StudySession.where(user_email: e, user_id: nil).update_all(user_id: id)
    AssignmentReestimate.where(user_email: e, user_id: nil).update_all(user_id: id)
    AssignmentAlert.where(user_email: e, user_id: nil).update_all(user_id: id)
  end
end
