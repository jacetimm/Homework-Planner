class SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :create

  def create
    auth = request.env["omniauth.auth"]

    user = User.find_or_initialize_by(google_uid: auth.uid)
    new_user = user.new_record?
    user.email        = auth.info.email
    user.name         = auth.info.name
    user.avatar_url   = auth.info.image
    user.access_token = auth.credentials.token
    # Google only sends refresh_token on first auth or when prompt=consent.
    user.refresh_token    = auth.credentials.refresh_token if auth.credentials.refresh_token.present?
    user.token_expires_at = auth.credentials.expires_at ? Time.at(auth.credentials.expires_at) : nil
    user.save!

    # Wire up any pre-existing rows keyed by email (data from before users table existed)
    user.backfill_email_records!

    session[:user_id] = user.id
    # Signal the dashboard to auto-detect and save the browser timezone on first login
    session[:detect_timezone] = true if new_user

    redirect_to session.delete(:return_to) || root_path,
      notice: "Welcome back! Your assignments are syncing from Google Classroom."
  end

  def failure
    message = params[:message].presence || request.env.dig("omniauth.error.type").to_s.presence

    alert =
      case message
      when "invalid_client", "unauthorized"
        "Google OAuth is misconfigured. Check the Google client ID and client secret in Rails credentials before signing in again."
      else
        "Authentication failed."
      end

    redirect_to root_path, alert: alert
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Logged out successfully."
  end
end
