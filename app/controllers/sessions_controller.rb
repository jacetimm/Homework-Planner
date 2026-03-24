class SessionsController < ApplicationController
  def create
    auth = request.env["omniauth.auth"]

    session[:access_token] = auth.credentials.token
    # Google only sends the refresh token on the very first auth or if prompt=consent is used.
    # We only want to set it if it exists so we don't accidentally overwrite a good one with nil.
    session[:refresh_token] = auth.credentials.refresh_token if auth.credentials.refresh_token.present?

    session[:user_email] = auth.info.email

    redirect_to root_path, notice: "Welcome back! Your assignments are syncing from Google Classroom."
  end

  def failure
    redirect_to root_path, alert: "Authentication failed."
  end

  def destroy
    session.clear
    redirect_to root_path, notice: "Logged out successfully."
  end
end
