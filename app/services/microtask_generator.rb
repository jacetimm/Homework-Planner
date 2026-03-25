require "net/http"
require "json"

class MicrotaskGenerator
  GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
  MODEL    = "llama-3.3-70b-versatile"

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You break a homework assignment into specific, actionable micro-tasks for a high school student.

    CRITICAL RULES — read carefully:
    1. Base EVERY task directly on the assignment description. If the description says "read two articles and answer 10 questions", your tasks must be "Read article 1", "Read article 2", "Answer questions 1–5", "Answer questions 6–10". NOT generic tasks like "outline main points" or "draft an introduction".
    2. If the description is blank or vague, use the title and course to infer the most likely concrete steps.
    3. Each task name must start with a strong verb: Write, Read, Solve, Outline, Research, Draft, Review, Complete, Watch, Calculate, etc.
    4. Task names must be SHORT (under 8 words) but specific. Bad: "Work on the essay". Good: "Write body paragraph 2 — evidence".
    5. Time estimates must be realistic and their SUM must equal the total estimated time exactly.
    6. Generate between 4 and 8 tasks. Never fewer, never more.
    7. Do NOT generate tasks like "Review assignment requirements", "Gather materials", "Read assignment prompt", or "Check your work" unless the description specifically requires them.
    8. If attachments exist (materials_count > 0), include a task for reviewing them.

    Return ONLY a valid JSON array — no markdown, no explanation, no extra text:
    [{"task": "Read chapter 7 (pages 112–130)", "minutes": 25}, {"task": "Answer questions 1–5", "minutes": 15}]
  PROMPT

  def initialize(api_key = nil)
    @api_key = api_key.presence || resolve_api_key
  end

  # Returns array of { "task" => String, "minutes" => Integer } or nil on failure
  def generate(title:, class_name:, estimated_minutes:, description: nil, materials_count: 0, materials_metadata: [], max_points: nil, due_date: nil)
    return nil if @api_key.blank?

    target_minutes = estimated_minutes.to_i
    return nil if target_minutes <= 0

    resolved_metadata = Array(materials_metadata).presence || []

    user_message = build_user_message(
      title:              title,
      class_name:         class_name,
      description:        description,
      materials_count:    resolved_metadata.any? ? resolved_metadata.size : materials_count.to_i,
      materials_metadata: resolved_metadata,
      max_points:         max_points,
      estimated_minutes:  estimated_minutes,
      due_date:           due_date
    )

    content = call_groq(user_message)
    parse_tasks(content, target_minutes)
  rescue StandardError => e
    Rails.logger.error("[MicrotaskGenerator] Error: #{e.message}")
    nil
  end

  private

  def build_user_message(title:, class_name:, description:, materials_count:, materials_metadata:, max_points:, estimated_minutes:, due_date:)
    parts = []
    parts << "Course: #{class_name}"
    parts << "Assignment title: #{title}"

    desc = description.to_s.strip
    if desc.present?
      parts << "Assignment description:\n#{desc}"
    else
      parts << "Assignment description: (none provided — infer tasks from the title and course)"
    end

    parts << "Total estimated time: #{estimated_minutes} minutes"
    parts << "The total time across all micro-tasks MUST equal exactly #{estimated_minutes} minutes. Do not exceed it."
    parts << "Point value: #{max_points} points" if max_points.to_i > 0

    if materials_metadata.any?
      lines = materials_metadata.map.with_index(1) do |m, i|
        type_label = case m["type"] || m[:type]
                     when "drive_file"    then "Google Drive file"
                     when "link"         then "Link"
                     when "youtube_video" then "YouTube video"
                     when "form"         then "Google Form"
                     else "Attachment"
                     end
        title_str = m["title"] || m[:title] || "Untitled"
        snippet   = m["content_snippet"] || m[:content_snippet]
        pages     = m["page_count"] || m[:page_count]
        questions = m["question_count"] || m[:question_count]
        headers   = m["section_headers"] || m[:section_headers]
        mime      = m["mime_type"] || m[:mime_type]

        if snippet.present?
          fmt = mime_format_label(mime)
          meta_parts = []
          meta_parts << fmt if fmt
          meta_parts << "#{pages} pages" if pages.to_i > 0
          meta_parts << "~#{questions} questions" if questions.to_i > 0
          meta_info = meta_parts.any? ? " (#{meta_parts.join(", ")})" : ""

          entry_lines = ["  #{i}. #{type_label}: #{title_str}#{meta_info}"]
          entry_lines << "     Headers: #{Array(headers).first(5).join(", ")}" if Array(headers).any?
          entry_lines << "     Content preview: #{snippet.to_s.strip[0, 300].inspect}"
          entry_lines.join("\n")
        else
          "  #{i}. #{type_label}: #{title_str}"
        end
      end
      parts << "Attached materials (#{materials_metadata.size} total):\n#{lines.join("\n")}"
    elsif materials_count > 0
      parts << "Number of attachments/materials: #{materials_count}"
    end

    parts << "Due: #{due_date}" if due_date.present?

    parts.join("\n")
  end

  def mime_format_label(mime)
    case mime.to_s
    when "application/pdf" then "PDF"
    when "application/vnd.google-apps.document" then "Google Doc"
    when "application/vnd.google-apps.presentation" then "Google Slides"
    else nil
    end
  end

  def call_groq(user_message)
    uri  = URI(GROQ_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.open_timeout = 5
    http.read_timeout = 15

    store = OpenSSL::X509::Store.new
    store.set_default_paths
    http.cert_store  = store
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER

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
      max_tokens:  500
    }.to_json

    response = http.request(req)
    raise "Groq HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    body    = JSON.parse(response.body)
    content = body.dig("choices", 0, "message", "content").to_s.strip
    content.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "").strip
  end

  def parse_tasks(content, target_minutes)
    tasks = JSON.parse(content)
    return nil unless tasks.is_a?(Array) && tasks.any?

    parsed = tasks.filter_map do |t|
      next unless t.is_a?(Hash) && t["task"].present?
      minutes = t["minutes"].to_i
      next if minutes <= 0

      { "task" => t["task"].to_s.strip, "minutes" => minutes.clamp(1, 120) }
    end

    normalize_task_minutes(parsed, target_minutes)
  rescue JSON::ParserError => e
    Rails.logger.error("[MicrotaskGenerator] Parse error: #{e.message} — raw: #{content.inspect}")
    nil
  end

  def normalize_task_minutes(tasks, target_minutes)
    return nil if tasks.blank? || target_minutes.to_i <= 0

    tasks = compact_task_count(tasks, target_minutes)
    total = tasks.sum { |task| task["minutes"].to_i }
    return nil if total <= 0

    scaled = tasks.map do |task|
      raw_minutes = (task["minutes"].to_f / total) * target_minutes
      task.merge("_raw_minutes" => raw_minutes)
    end

    normalized = scaled.map do |task|
      task.merge("minutes" => task["_raw_minutes"].floor)
    end

    remainder = target_minutes - normalized.sum { |task| task["minutes"] }
    if remainder.positive?
      normalized
        .sort_by { |task| -(task["_raw_minutes"] - task["minutes"]) }
        .first(remainder)
        .each { |task| task["minutes"] += 1 }
    elsif remainder.negative?
      normalized
        .select { |task| task["minutes"] > 1 }
        .sort_by { |task| task["_raw_minutes"] - task["minutes"] }
        .first(remainder.abs)
        .each { |task| task["minutes"] -= 1 }
    end

    normalized.each { |task| task.delete("_raw_minutes") }

    # Guard the exact total even after rounding adjustments.
    delta = target_minutes - normalized.sum { |task| task["minutes"] }
    if delta != 0 && normalized.any?
      normalized.last["minutes"] += delta
    end

    normalized.presence
  end

  def compact_task_count(tasks, target_minutes)
    compacted = tasks.dup
    max_tasks = [target_minutes.to_i, 1].max

    while compacted.size > max_tasks
      tail = compacted.pop
      compacted[-1] = {
        "task" => "#{compacted[-1]["task"]} + #{tail["task"]}",
        "minutes" => compacted[-1]["minutes"].to_i + tail["minutes"].to_i
      }
    end

    compacted
  end

  def resolve_api_key
    Rails.application.credentials.groq_api_key.to_s.strip.presence
  end
end
