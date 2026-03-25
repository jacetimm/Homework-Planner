class Rack::Attack
  # ── Safelists ──────────────────────────────────────────────────────────────

  # Never throttle requests from localhost (development / test).
  safelist("allow-localhost") do |req|
    req.ip == "127.0.0.1" || req.ip == "::1"
  end

  # ── Throttles ──────────────────────────────────────────────────────────────

  # 1. General: 60 requests per minute per IP.
  #    Baseline protection against scraping and accidental hammering.
  throttle("req/ip", limit: 60, period: 1.minute, &:ip)

  # 2. Login: 5 OAuth callback attempts per minute per IP.
  #    The OAuth callback is the only login surface in this app.
  throttle("login/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path == "/auth/google_oauth2/callback"
  end

  # 3. AI re-estimate: 10 per day per user session.
  #    Mirrors the existing AssignmentReestimate::DAILY_LIMIT so middleware
  #    and model logic stay in sync.
  throttle("reestimate/user", limit: 10, period: 24.hours) do |req|
    if req.path.match?(%r{/assignments/.+/reestimate}) && req.post?
      req.session["user_id"]
    end
  end

  # 4. Groq-powered endpoints: 20 per hour per user session.
  #    Covers microtask generation (/crunch/:id/microtasks) and the
  #    synchronous re-estimate path which calls EstimateAssignmentsJob.
  GROQ_PATHS = %r{/crunch/.+/microtasks|/assignments/.+/reestimate}

  throttle("groq/user", limit: 20, period: 1.hour) do |req|
    if req.path.match?(GROQ_PATHS)
      req.session["user_id"]
    end
  end

  # ── 429 response ──────────────────────────────────────────────────────────

  # Rack::Attack 6.x calls throttled_responder with a Rack::Attack::Request
  # (which inherits Rack::Request), not a raw env hash.
  self.throttled_responder = lambda do |req|
    match_data  = req.env["rack.attack.match_data"] || {}
    retry_after = match_data[:period].to_i

    headers = {
      "Content-Type" => "text/plain",
      "Retry-After"  => retry_after.to_s
    }

    message = if req.path.match?(GROQ_PATHS)
      "Slow down! You've used up your AI requests for now. Try again later."
    else
      "Slow down! Too many requests. Try again in a minute."
    end

    [429, headers, [message]]
  end
end

# Mount the middleware (no-op if already inserted by Railtie, harmless either way).
Rails.application.config.middleware.use Rack::Attack
