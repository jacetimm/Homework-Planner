require "pdf/reader"

class DriveContentExtractor
  SNIPPET_LENGTH   = 2000
  MAX_HEADERS      = 10
  SHORT_LINE_MAX   = 60

  def initialize(access_token)
    @access_token = access_token
  end

  # Returns enriched copy of materials_metadata array.
  # Non-drive-file entries and already-extracted entries are passed through unchanged.
  def enrich_materials(materials_metadata)
    Array(materials_metadata).map do |mat|
      mat = mat.is_a?(Hash) ? mat.dup : mat
      next mat unless (mat["type"] || mat[:type]) == "drive_file"
      next mat if mat["content_extracted"] == true || mat[:content_extracted] == true

      drive_id = mat["drive_id"] || mat[:drive_id]
      next mat if drive_id.blank?

      enrich_entry(mat, drive_id)
    end
  end

  private

  def drive_service
    @drive_service ||= begin
      service = Google::Apis::DriveV3::DriveService.new
      service.authorization = build_auth
      service
    end
  end

  def build_auth
    require "googleauth"
    Google::Auth::UserRefreshCredentials.new(
      access_token: @access_token
    )
  end

  def enrich_entry(mat, drive_id)
    file_meta = drive_service.get_file(drive_id, fields: "id,name,mimeType")
    mime_type  = file_meta.mime_type.to_s

    mat["mime_type"] = mime_type

    raw_text = extract_text(drive_id, mime_type)

    if raw_text
      mat["page_count"]       = estimate_page_count(raw_text, mime_type)
      mat["question_count"]   = count_questions(raw_text)
      mat["section_headers"]  = extract_headers(raw_text)
      mat["content_snippet"]  = raw_text.strip[0, SNIPPET_LENGTH]
    end

    mat["content_extracted"] = true
    Rails.logger.info("[DriveContentExtractor] Enriched drive_id=#{drive_id} mime=#{mime_type} pages=#{mat["page_count"]} questions=#{mat["question_count"]}")
    mat
  rescue StandardError => e
    Rails.logger.warn("[DriveContentExtractor] Skipping drive_id=#{drive_id}: #{e.message}")
    mat
  end

  def extract_text(drive_id, mime_type)
    case mime_type
    when "application/pdf"
      extract_pdf(drive_id)
    when "application/vnd.google-apps.document", "application/vnd.google-apps.presentation"
      export_as_text(drive_id)
    else
      nil
    end
  end

  def extract_pdf(drive_id)
    io = StringIO.new
    drive_service.get_file(drive_id, download_dest: io)
    io.rewind

    reader = PDF::Reader.new(io)
    @pdf_page_count = reader.page_count
    reader.pages.map(&:text).join("\n")
  rescue StandardError => e
    Rails.logger.warn("[DriveContentExtractor] PDF extraction failed for #{drive_id}: #{e.message}")
    nil
  end

  def export_as_text(drive_id)
    io = StringIO.new
    drive_service.export_file(drive_id, "text/plain", download_dest: io)
    io.rewind
    io.read
  rescue StandardError => e
    Rails.logger.warn("[DriveContentExtractor] Export failed for #{drive_id}: #{e.message}")
    nil
  end

  def estimate_page_count(text, mime_type)
    return @pdf_page_count if @pdf_page_count
    # Estimate by form-feed characters or every ~3000 chars for exports
    page_breaks = text.scan(/\f/).size
    page_breaks > 0 ? page_breaks + 1 : [(text.length / 3000.0).ceil, 1].max
  end

  def count_questions(text)
    numbered = text.scan(/^\s*\d+[\.\)]/).size
    question_marks = text.scan(/[^.!?]*\?/).size
    [numbered, question_marks].max
  end

  def extract_headers(text)
    lines = text.split("\n").map(&:strip).reject(&:empty?)
    headers = lines.select do |line|
      next false if line.length > SHORT_LINE_MAX
      # ALL CAPS line or short standalone line that looks like a header
      line == line.upcase && line.match?(/[A-Z]/) ||
        line.length <= SHORT_LINE_MAX && !line.match?(/[.?!,]$/) && !line.match?(/^\d+[\.\)]/)
    end
    headers.uniq.first(MAX_HEADERS)
  end
end
