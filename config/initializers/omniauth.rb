OmniAuth.config.on_failure = proc { |env| SessionsController.action(:failure).call(env) }
OmniAuth.config.failure_raise_out_environments = []

# OmniAuth v2 requires POST for the initiation route by default.
# Allow GET so a standard link to /auth/google_oauth2 still works.
OmniAuth.config.allowed_request_methods = %i[post get]
OmniAuth.config.silence_get_warning = true

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           Rails.application.credentials.dig(:google, :client_id),
           Rails.application.credentials.dig(:google, :client_secret), {
    scope: "email,profile,https://www.googleapis.com/auth/classroom.courses.readonly,https://www.googleapis.com/auth/classroom.coursework.me.readonly,https://www.googleapis.com/auth/classroom.student-submissions.me.readonly,https://www.googleapis.com/auth/calendar.readonly",
    # "consent" forces the full OAuth flow without the prompt=none edge case
    # that causes the session state to be lost and bytesize to fail on nil
    prompt: "consent",
    access_type: "offline",
    # Allows re-using a session that already has Classroom scopes when Calendar is added
    include_granted_scopes: true,
    # Prevents a second crash in some omniauth-google-oauth2 versions during JWT decode
    skip_jwt: false
  }
end
