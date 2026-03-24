# Explicitly set SameSite: :lax so the session cookie is sent on
# cross-origin top-level redirects (e.g. the Google OAuth callback).
# Without this, some browsers won't send the session cookie when Google
# redirects back to /auth/google_oauth2/callback, making omniauth.state nil
# and causing the 'undefined method bytesize for nil' crash.
Rails.application.config.session_store :cookie_store,
  key: "_homework_planner_session",
  same_site: :lax,
  secure: Rails.env.production?
