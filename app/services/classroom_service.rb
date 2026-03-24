require "google/apis/classroom_v1"

class ClassroomService
  # Temporary fallback shown until Groq AI estimates are fetched and cached.
  DEFAULT_ESTIMATED_MINUTES = TimeEstimator::DEFAULT_MINUTES

  # States that mean the student has NOT yet finished this assignment.
  # TURNED_IN and RETURNED are explicitly excluded.
  # NEW is excluded — Google sometimes uses it for re-submitted items.
  ACTIONABLE_STATES = %w[CREATED RECLAIMED_BY_STUDENT UNKNOWN].freeze

  def initialize(access_token, user_setting = nil)
    @service = Google::Apis::ClassroomV1::ClassroomService.new
    @service.authorization = access_token
    @user_setting = user_setting || UserSetting.new
  end

  def courses
    @courses ||= fetch_active_courses
  end

  # Returns a hash with keys: :tonight_plan, :tonight_summary, :upcoming, :weekly_preview
  def assignments(busy_blocks: [])
    all_assignments = []

    courses.each do |course|
      fetch_course_work(course.id).each do |work|
        # --- PART 1: Submission state filtering ---
        # fetch_student_submissions rescues internally and returns [] on failure.
        submissions = fetch_student_submissions(course.id, work.id)
        state = submissions.first&.state || "UNKNOWN"

        if submissions.empty?
          Rails.logger.warn("[Classroom] No submission found for work #{work.id} in course #{course.id} — treating as UNKNOWN")
        else
          Rails.logger.info("[Classroom] work #{work.id} state=#{state}")
        end

        # Skip anything that isn't clearly actionable
        next unless ACTIONABLE_STATES.include?(state)

        desc               = work.description.to_s
        materials_metadata = extract_materials_metadata(work.materials)
        materials_count    = materials_metadata.size

        # --- PART 2: Links ---
        # Use the API-provided alternate_link (guaranteed by Google to be correct).
        # Fall back to the course page if the assignment link is missing.
        assignment_link = work.alternate_link.presence || course.alternate_link

        all_assignments << {
          class_name:         course.name,
          course_link:        course.alternate_link,
          title:              work.title,
          assignment_link:    assignment_link,
          description:        desc,
          materials_count:    materials_count,
          materials_metadata: materials_metadata,
          max_points:         work.max_points.to_i,
          due_date:           parse_due_date(work.due_date, work.due_time),
          state:              state,
          course_id:          course.id,
          course_work_id:     work.id
        }
      end
    rescue StandardError => e
      raise_if_auth_error(e)
      Rails.logger.error("[Classroom] Failed to process course #{course.id} (#{course.name}): #{e.message}")
    end

    # Seed with a neutral fallback until AI estimates are loaded.
    all_assignments.each do |a|
      a[:estimated_minutes] = DEFAULT_ESTIMATED_MINUTES
    end

    all_assignments
  end

  private

  # Converts the Google Classroom materials array into a flat array of hashes:
  #   [{ title: String, type: String }]
  # Type is one of: "drive_file", "link", "youtube_video", "form"
  def extract_materials_metadata(materials)
    return [] if materials.nil?

    materials.filter_map do |mat|
      if (df = mat.drive_file&.drive_file)
        { title: df.title.to_s.presence || "Untitled file", type: "drive_file" }
      elsif (link = mat.link)
        { title: link.title.to_s.presence || link.url.to_s, type: "link" }
      elsif (yt = mat.youtube_video)
        { title: yt.title.to_s.presence || "YouTube video", type: "youtube_video" }
      elsif (form = mat.form)
        { title: form.title.to_s.presence || "Google Form", type: "form" }
      end
    end
  end

  def raise_if_auth_error(e)
    raise e if e.is_a?(Google::Apis::AuthorizationError)
    raise e if e.is_a?(Google::Apis::ClientError) && (e.status_code == 401 || e.message.to_s.include?("Invalid Credentials") || e.message.to_s.include?("Unauthorized"))
  end

  def fetch_active_courses
    response = @service.list_courses(course_states: [ "ACTIVE" ])
    response.courses || []
  rescue StandardError => e
    raise_if_auth_error(e)
    Rails.logger.error("[Classroom] Failed to fetch courses: #{e.message}")
    []
  end

  def fetch_course_work(course_id)
    response = @service.list_course_works(course_id)
    response.course_work || []
  rescue StandardError => e
    raise_if_auth_error(e)
    Rails.logger.error("[Classroom] Failed to fetch coursework for #{course_id}: #{e.message}")
    []
  end

  # Fetch THIS student's submission only (user_id: "-" = the caller).
  def fetch_student_submissions(course_id, course_work_id)
    response = @service.list_student_submissions(course_id, course_work_id, user_id: "-")
    response.student_submissions || []
  rescue StandardError => e
    raise_if_auth_error(e)
    Rails.logger.error("[Classroom] Failed to fetch submissions for work #{course_work_id}: #{e.message}")
    []
  end

  # Classroom due dates should remain plain calendar dates.
  # We intentionally keep only year/month/day to avoid timezone day-shift bugs.
  def parse_due_date(date, time)
    return nil if date.nil? || date.year.nil? || date.month.nil? || date.day.nil?

    if time
      utc_time = Time.utc(date.year, date.month, date.day, time.hours || 0, time.minutes || 0)
      utc_time.in_time_zone(Time.zone).to_date
    else
      Date.new(date.year, date.month, date.day)
    end
  rescue StandardError => e
    Rails.logger.error("[Classroom] Failed to parse due date: #{e.message}")
    nil
  end

end
