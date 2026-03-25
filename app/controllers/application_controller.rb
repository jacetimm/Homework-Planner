require "oauth2"

class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  before_action :set_time_zone

  helper_method :current_user

  def set_time_zone
    tz = current_user&.timezone.presence || "Eastern Time (US & Canada)"
    Time.zone = ActiveSupport::TimeZone[tz] || ActiveSupport::TimeZone["Eastern Time (US & Canada)"]
  end

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: session[:user_id]) if session[:user_id]
  end

  # Catch expired/invalid tokens from Google Classroom or Calendar API
  rescue_from "Google::Apis::AuthorizationError", with: :reauthenticate
  rescue_from "Google::Apis::ClientError" do |exception|
    if exception.message.include?("Invalid Credentials") || exception.message.include?("401")
      reauthenticate
    else
      raise exception
    end
  end
  rescue_from "OAuth2::Error", with: :handle_oauth2_error

  private

  def reauthenticate(exception = nil)
    if current_user&.refresh_token.present?
      begin
        current_user.refresh_access_token!
        redirect_back(fallback_location: root_path)
        return
      rescue OAuth2::Error, ActiveRecord::RecordInvalid => e
        Rails.logger.error "[AUTH] Token refresh failed: #{e.class} #{e.message}"
      rescue => e
        Rails.logger.error "[AUTH] Unexpected token refresh error: #{e.class} #{e.message}\n#{e.backtrace.first(3).join("\n")}"
        raise
      end
    end

    reset_session
    redirect_to root_path, alert: "Your Google session expired. Please log in again to sync your assignments."
  end

  def handle_oauth2_error(exception)
    Rails.logger.error "[AUTH] OAuth2 error: #{exception.message}"
    reset_session
    redirect_to root_path, alert: "Google sign-in expired or was revoked. Please connect your Google account again."
  end
end
