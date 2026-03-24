require "oauth2"

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  before_action :set_time_zone

  def set_time_zone
    Time.zone = "America/New_York"
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

  private

  def reauthenticate(exception = nil)
    if session[:refresh_token].present?
      begin
        client = OAuth2::Client.new(
          ENV["GOOGLE_CLIENT_ID"],
          ENV["GOOGLE_CLIENT_SECRET"],
          {
            site: "https://accounts.google.com",
            token_url: "/o/oauth2/token"
          }
        )
        token = OAuth2::AccessToken.new(
          client,
          session[:access_token],
          refresh_token: session[:refresh_token]
        )
        new_token = token.refresh!

        session[:access_token] = new_token.token
        session[:refresh_token] = new_token.refresh_token if new_token.refresh_token.present?

        # Silently retry the user's last request with the new access token
        redirect_back(fallback_location: root_path)
        return
      rescue StandardError => e
        Rails.logger.error "[AUTH] Token refresh failed: #{e.message}"
        # Fall through to hard reset if refresh is revoked or fails
      end
    end

    # Clear the dead token and force manual sign-in
    reset_session
    redirect_to root_path, alert: "Your Google session expired. Please log in again to sync your assignments."
  end
end
