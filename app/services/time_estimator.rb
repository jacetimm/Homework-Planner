require "net/http"
require "json"

class TimeEstimator
  GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
  MODEL    = "llama-3.3-70b-versatile"
  DEFAULT_MINUTES = 30
  MIN_MINUTES = 5
  MAX_MINUTES = 480

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You estimate homework completion time for a typical high school student working alone at home.

    Estimate only the student's active work time. Do not include class time, travel, waiting, printing, or vague procrastination buffers.

    Calibration rules:
    - 1-3 short questions: usually 5-15 minutes.
    - 5-10 routine questions/problems: usually 15-35 minutes.
    - 20-30 routine problems: usually 45-75 minutes.
    - Reading 1 chapter: usually 25-45 minutes unless the text explicitly sounds dense or annotated.
    - 1 page of polished writing: usually 30-45 minutes.
    - 2 pages of polished writing: usually 45-75 minutes.
    - A project, presentation, lab report, or multi-step task can be 60-180+ minutes.
    - If the assignment text says "brief", "quick", "short", "simple", or "just", bias lower.
    - Do NOT inflate time just because the class is AP, honors, advanced, or difficult. Use the actual task scope.
    - If a teacher gives an explicit expected time, treat that as the strongest signal.

    Return ONLY valid JSON with this exact shape:
    {"minutes": <integer>, "reasoning": "<one short sentence>"}
  PROMPT

  def initialize(api_key = nil)
    @api_key = api_key.presence || resolve_api_key
  end

  # Returns { minutes: Integer, reasoning: String, source: String }
  def estimate(title:, description:, class_name:)
    if @api_key.blank?
      Rails.logger.warn("[TimeEstimator] GROQ_API_KEY not set — using default")
      return fallback_result("No API key configured")
    end

    clean_description = sanitize_text(description)

    content = call_groq(
      build_user_message(title, clean_description, class_name)
    )

    parsed = parse_response(content)
    reasoning = parsed[:reasoning].presence || "Estimated from assignment scope"
    result = { minutes: parsed[:minutes], reasoning: reasoning, source: "groq" }
    Rails.logger.info("[TimeEstimator] source=groq title=#{title.to_s.inspect} minutes=#{result[:minutes]} reasoning=#{reasoning}")
    result
  rescue StandardError => e
    Rails.logger.error("[TimeEstimator] Groq API error (#{e.class}): #{e.message}")
    fallback_result("API error — used default")
  end

  private

  def build_user_message(title, description, class_name)
    desc = description.presence || "(no description provided — estimate based on title and course)"
    parts = []
    parts << "Course: #{class_name}"
    parts << "Title: #{title}"
    parts << "Description: #{desc}"
    parts << "\nEstimate the likely total minutes and keep it realistic for a normal student."
    parts.join("\n")
  end

  def call_groq(user_message)
    uri  = URI(GROQ_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.open_timeout = 5
    http.read_timeout = 15

    # Use system cert store without CRL checking, which fails on macOS due to
    # OpenSSL attempting to fetch a CRL it cannot reach.
    store = OpenSSL::X509::Store.new
    store.set_default_paths
    http.cert_store   = store
    http.verify_mode  = OpenSSL::SSL::VERIFY_PEER

    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{@api_key}"
    req["Content-Type"]  = "application/json"
    req.body = {
      model: MODEL,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user",   content: user_message }
      ],
      temperature: 0.3,
      max_tokens:  150
    }.to_json

    response = http.request(req)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error("[TimeEstimator] HTTP #{response.code}: #{response.body}")
      raise "Groq returned HTTP #{response.code}"
    end

    body = JSON.parse(response.body)
    content = body.dig("choices", 0, "message", "content")
    raise "Empty content in Groq response" if content.blank?

    # Strip markdown code fences if the model wrapped its answer in ```json ... ```
    content.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "").strip
  end

  def parse_response(content)
    result  = JSON.parse(content)
    minutes = normalize_minutes(result["minutes"])
    { minutes: minutes, reasoning: result["reasoning"].to_s }
  rescue JSON::ParserError => e
    Rails.logger.error("[TimeEstimator] JSON parse failed: #{e.message} — raw: #{content.inspect}")
    fallback_result("Parse error — used default")
  end

  def sanitize_text(text)
    text.to_s.gsub(/<[^>]+>/, " ").gsub(/&[a-z]+;/i, " ").gsub(/\s+/, " ").strip
  end

  def normalize_minutes(value)
    minutes = value.to_i
    minutes = DEFAULT_MINUTES unless minutes.positive?
    minutes = [ [ minutes, MIN_MINUTES ].max, MAX_MINUTES ].min
    ((minutes / 5.0).round * 5).to_i
  end

  def fallback_result(reasoning)
    { minutes: DEFAULT_MINUTES, reasoning: reasoning, source: "fallback" }
  end

  def resolve_api_key
    Rails.application.credentials.groq_api_key.to_s.strip.presence
  end
end
