class DashboardBuilder
  Result = Struct.new(
    :courses,
    :schedule,
    :tonight_assignments,
    :tonight_summary,
    :weekly_preview,
    :danger_zone,
    :danger_zone_ids,
    :streak,
    :calibration_nudges,
    :any_pending_estimates,
    :syncing,
    keyword_init: true
  )

  def initialize(current_user)
    @current_user  = current_user
    @user_setting  = UserSetting.for_user(current_user)
    @calibration_nudges = []
    @syncing = false
  end

  def call
    courses, all_assignments = fetch_assignments
    merge_estimates(all_assignments)
    apply_calibration(all_assignments)
    enrich_metadata(all_assignments)

    nightly_capacity, tonight_capacity, calendar_blocks = compute_capacity

    schedule = build_schedule(all_assignments, nightly_capacity, tonight_capacity, calendar_blocks)

    today_data = schedule[Date.current.to_s]
    annotate_reestimate_limits!(today_data[:assignments])

    danger = detect_danger_zone(all_assignments)

    Result.new(
      courses:                courses,
      schedule:               schedule,
      tonight_assignments:    today_data[:assignments],
      tonight_summary:        build_tonight_summary(today_data, schedule, tonight_capacity),
      weekly_preview:         build_weekly_preview(schedule),
      danger_zone:            danger,
      danger_zone_ids:        danger.map { |a| a[:course_work_id] }.to_set,
      streak:                 calculate_streak,
      calibration_nudges:     @calibration_nudges,
      any_pending_estimates:  all_assignments.any? { |a| a[:estimate_source] == :pending },
      syncing:                @syncing
    )
  end

  private

  # ---------------------------------------------------------------------------
  # Fetching
  # ---------------------------------------------------------------------------

  def fetch_assignments
    cache = ClassroomCache.find_or_initialize_by(user_id: @current_user.id)

    if cache.fresh?
      return [ cache.courses, cache.assignments ]
    end

    if cache.persisted?
      # Stale — serve cached data instantly and refresh in background
      @syncing = true
      SyncClassroomJob.perform_later(@current_user.id)
      return [ cache.courses, cache.assignments ]
    end

    # No cache yet (first load) — fetch synchronously and populate cache
    classroom_service = ClassroomService.new(@current_user.access_token, @user_setting)
    courses     = classroom_service.courses
    assignments = classroom_service.assignments
    cache.store!(courses: courses, assignments: assignments)
    [ courses, assignments ]
  end

  # ---------------------------------------------------------------------------
  # Estimates
  # ---------------------------------------------------------------------------

  def merge_estimates(all_assignments)
    course_work_ids = all_assignments.map { |a| a[:course_work_id] }
    cached = AssignmentEstimate.cached_minutes_for(@current_user.email, course_work_ids)
    all_assignments.each do |a|
      if (est = cached[a[:course_work_id]])
        a[:estimated_minutes] = est.estimated_minutes
        a[:estimate_source]   = est.reasoning == "Set manually by student" ? :manual : :ai
      else
        a[:estimate_source] = :pending
      end
    end

    uncached = all_assignments.reject { |a| cached.key?(a[:course_work_id]) }
    if uncached.any?
      serializable = uncached.map do |a|
        {
          "course_work_id"  => a[:course_work_id],
          "title"           => a[:title].to_s,
          "description"     => a[:description].to_s,
          "class_name"      => a[:class_name].to_s,
          "materials_count" => a[:materials_count].to_i,
          "max_points"      => a[:max_points].to_i,
          "due_date"        => a[:due_date]&.to_s
        }
      end
      EstimateAssignmentsJob.perform_later(@current_user.email, serializable)
      # Assignments with no estimate yet show :pending until the background job completes
    end
  end

  # ---------------------------------------------------------------------------
  # Calibration
  # ---------------------------------------------------------------------------

  def apply_calibration(all_assignments)
    calibration_cap = 3.0
    calibration = StudySession.calibration_factors(@current_user.email)
    return unless calibration.any?

    all_assignments.each do |a|
      factor = calibration[a[:class_name]]
      next unless factor
      a[:estimated_minutes] = [(a[:estimated_minutes].to_i * [factor, calibration_cap].min).round, 1].max
    end

    @calibration_nudges = calibration.filter_map do |course, factor|
      { course: course, factor: factor.round(1) } if factor >= calibration_cap
    end
  end

  # ---------------------------------------------------------------------------
  # Metadata backfill (keeps cached estimates up to date with latest API data)
  # ---------------------------------------------------------------------------

  def enrich_metadata(all_assignments)
    all_estimates = AssignmentEstimate.where(
      user_email:     @current_user.email,
      course_work_id: all_assignments.map { |a| a[:course_work_id] }
    ).index_by(&:course_work_id)

    all_assignments.each do |a|
      est = all_estimates[a[:course_work_id]]
      next unless est

      cols = {}
      cols[:description]     = a[:description].to_s.first(2000) if est.description.blank?
      cols[:materials_count] = a[:materials_count].to_i          if est.materials_count.blank?
      cols[:max_points]      = a[:max_points].to_i               if est.max_points.blank?
      cols[:title]           = a[:title].to_s.first(255)         if est.title.blank?
      cols[:class_name]      = a[:class_name].to_s.first(255)    if est.class_name.blank?
      cols[:due_date]        = a[:due_date]                      if est.due_date.blank? && a[:due_date].present?
      est.update_columns(cols) if cols.any?
    end
  end

  # ---------------------------------------------------------------------------
  # Capacity (nightly + tonight + calendar blocks)
  # ---------------------------------------------------------------------------

  def compute_capacity
    study_start      = @user_setting.study_start_time
    study_end        = @user_setting.study_end_time
    start_m          = study_start.hour * 60 + study_start.min
    orig_end_m       = study_end.hour * 60 + study_end.min
    crosses_midnight = orig_end_m < start_m

    nightly_capacity = crosses_midnight ? (orig_end_m + 1440 - start_m) : [orig_end_m - start_m, 0].max

    window_start_at, window_end_at = tonight_window_bounds(study_start, study_end)
    calendar_blocks = fetch_calendar_blocks(window_start_at, window_end_at, start_m, orig_end_m, crosses_midnight)

    now_m = Time.current.hour * 60 + Time.current.min
    remaining = if crosses_midnight
      if now_m >= start_m
        [orig_end_m + 1440 - now_m, 0].max
      elsif now_m <= orig_end_m
        [orig_end_m - now_m, 0].max
      else
        nightly_capacity
      end
    else
      if now_m < start_m
        nightly_capacity
      elsif now_m <= orig_end_m
        orig_end_m - now_m
      else
        0
      end
    end

    window_start   = crosses_midnight ? (now_m >= start_m ? now_m : start_m) : [now_m, start_m].max
    window_end     = crosses_midnight ? orig_end_m + 1440 : orig_end_m
    extra_reduction = total_blocked_minutes(
      manual_busy_blocks(start_m, orig_end_m, crosses_midnight),
      calendar_blocks,
      window_start,
      window_end
    )

    tonight_capacity = [[remaining, nightly_capacity].min - extra_reduction, 0].max

    [nightly_capacity, tonight_capacity, calendar_blocks]
  end

  def fetch_calendar_blocks(window_start_at, window_end_at, start_m, end_m, crosses_midnight)
    return [] unless @user_setting.block_google_calendar_events?
    return [] if window_start_at.blank? || window_end_at.blank? || window_start_at >= window_end_at

    cal_cache = CalendarCache.find_or_initialize_by(user_id: @current_user.id)
    busy_blocks = if cal_cache.fresh?
      cal_cache.blocks
    else
      raw = CalendarService.new(@current_user.access_token).busy_blocks_between(
        start_time:            window_start_at,
        end_time:              window_end_at,
        ignored_keywords:      @user_setting.calendar_ignored_keywords,
        ignored_calendar_ids:  @user_setting.ignored_google_calendar_ids,
        ignore_rules:          @user_setting.calendar_ignore_rules
      )
      cal_cache.store!(blocks: raw)
      raw
    end

    session_anchor = session_anchor_date(window_start_at, start_m, end_m, crosses_midnight)
    busy_blocks.filter_map do |block|
      start_minutes = timeline_minutes_for(block[:start], session_anchor, crosses_midnight)
      end_minutes   = timeline_minutes_for(block[:end],   session_anchor, crosses_midnight)
      next if end_minutes <= start_minutes

      {
        type:    "calendar",
        label:   block[:calendar_name].present? ? "#{block[:label]} (#{block[:calendar_name]})" : block[:label],
        start_m: start_minutes,
        end_m:   end_minutes
      }
    end
  rescue StandardError => e
    raise e if e.is_a?(Google::Apis::AuthorizationError) ||
               (e.is_a?(Google::Apis::ClientError) && (e.status_code == 401 || e.message.to_s.include?("Unauthorized") || e.message.to_s.include?("Invalid Credentials")))
    Rails.logger.error("[Dashboard] Failed to load calendar blocks: #{e.message}")
    []
  end

  def manual_busy_blocks(start_m, end_m, crosses_midnight)
    today_name = Date.current.strftime("%A")
    Array(@user_setting.extracurricular_blocks).filter_map do |block|
      days = block_days(block)
      next unless days.include?(today_name)

      block_start = parse_minutes(block["start_time"] || block[:start_time])
      block_end   = parse_minutes(block["end_time"]   || block[:end_time])
      next if block_start.nil? || block_end.nil?

      if crosses_midnight
        block_start += 1440 if block_start < start_m
        block_end   += 1440 if block_end   < start_m
      end

      next unless block_start < (crosses_midnight ? end_m + 1440 : end_m)

      { start_m: block_start, end_m: block_end }
    end
  end

  # ---------------------------------------------------------------------------
  # Schedule
  # ---------------------------------------------------------------------------

  def build_schedule(all_assignments, nightly_capacity, tonight_capacity, calendar_blocks)
    HomeworkScheduler.new(
      nightly_capacity:       nightly_capacity,
      tonight_capacity:       tonight_capacity,
      study_start_time:       @user_setting.study_start_time,
      study_end_time:         @user_setting.study_end_time,
      break_frequency:        @user_setting.break_frequency.to_i,
      break_duration:         @user_setting.break_duration.to_i,
      extracurricular_blocks: @user_setting.extracurricular_blocks || [],
      hard_subjects:          @user_setting.hard_subjects || [],
      calendar_busy_blocks:   calendar_blocks,
      max_per_subject:        @user_setting.max_minutes_per_subject.to_i
    ).schedule(all_assignments)
  end

  # ---------------------------------------------------------------------------
  # Summary builders
  # ---------------------------------------------------------------------------

  def build_tonight_summary(today_data, schedule, tonight_capacity)
    {
      assignment_count:   today_data[:assignments].size,
      total_minutes:      today_data[:total_minutes],
      total_free_minutes: today_data[:remaining_capacity],
      tonight_capacity:   tonight_capacity,
      fits:               schedule["wont_fit"].empty?,
      busiest_task:       today_data[:assignments].max_by { |a| a[:minutes] },
      pending_count:      today_data[:assignments].count { |a| a[:estimate_source] == :pending }
    }
  end

  def build_weekly_preview(schedule)
    {
      total_assignments: (0..6).sum { |o| schedule[(Date.current + o).to_s][:assignments].size },
      busiest_day:       schedule["busiest_day"] ? Date.parse(schedule["busiest_day"]) : nil
    }
  end

  # ---------------------------------------------------------------------------
  # Danger zone
  # ---------------------------------------------------------------------------

  def detect_danger_zone(all_assignments)
    started_ids = StudySession.where(user_email: @current_user.email).pluck(:course_work_id).to_set
    all_assignments.select do |a|
      due = Date.parse(a[:due_date]) rescue nil
      next false unless due
      days_left = (due - Date.current).to_i
      days_left <= 2 && a[:estimated_minutes].to_i >= 90 && !started_ids.include?(a[:course_work_id])
    end
  end

  # ---------------------------------------------------------------------------
  # Streak
  # ---------------------------------------------------------------------------

  def calculate_streak
    { count: @user_setting.streak_count, active: @user_setting.streak_active? }
  end

  # ---------------------------------------------------------------------------
  # Reestimate annotations
  # ---------------------------------------------------------------------------

  def annotate_reestimate_limits!(assignments)
    course_work_ids = Array(assignments).map { |a| a[:course_work_id].to_s }.reject(&:blank?).uniq
    counts     = AssignmentReestimate.counts_by_assignment_for(@current_user.email, course_work_ids)
    daily_left = AssignmentReestimate.remaining_today_for(@current_user.email)

    Array(assignments).each do |assignment|
      used           = counts[assignment[:course_work_id].to_s].to_i
      assignment_left = [AssignmentReestimate::ASSIGNMENT_LIMIT - used, 0].max
      tooltip = if assignment_left <= 0
        "Out of re-estimates. Use 'My est' to set it manually."
      elsif daily_left <= 0
        "Out of re-estimates today. Use 'My est' to set it manually."
      else
        "#{assignment_left}/#{AssignmentReestimate::ASSIGNMENT_LIMIT} re-estimates left for this assignment."
      end

      assignment[:reestimate_disabled]          = assignment_left <= 0 || daily_left <= 0
      assignment[:reestimate_tooltip]           = tooltip
      assignment[:assignment_reestimates_left]  = assignment_left
      assignment[:daily_reestimates_left]       = daily_left
      assignment[:daily_reestimates_limit]      = AssignmentReestimate::DAILY_LIMIT
    end
  end

  # ---------------------------------------------------------------------------
  # Time/window helpers
  # ---------------------------------------------------------------------------

  def tonight_window_bounds(study_start, study_end)
    now = Time.current
    session_start_today = now.change(hour: study_start.hour, min: study_start.min)
    session_end_today   = now.change(hour: study_end.hour,   min: study_end.min)

    if session_end_today <= session_start_today
      if now >= session_start_today
        session_start_at = session_start_today
        session_end_at   = session_end_today + 1.day
      elsif now <= session_end_today
        session_start_at = session_start_today - 1.day
        session_end_at   = session_end_today
      else
        session_start_at = session_start_today
        session_end_at   = session_end_today + 1.day
      end
    else
      session_start_at = session_start_today
      session_end_at   = session_end_today
    end

    [[now, session_start_at].max, session_end_at]
  end

  def total_blocked_minutes(manual_blocks, calendar_blocks, window_start, window_end)
    intervals = (Array(manual_blocks) + Array(calendar_blocks)).filter_map do |block|
      start_min = [block[:start_m].to_i, window_start].max
      end_min   = [block[:end_m].to_i,   window_end].min
      next if end_min <= start_min
      [start_min, end_min]
    end.sort_by(&:first)

    merged = []
    intervals.each do |start_min, end_min|
      if merged.empty? || start_min > merged.last[1]
        merged << [start_min, end_min]
      else
        merged.last[1] = [merged.last[1], end_min].max
      end
    end

    merged.sum { |start_min, end_min| end_min - start_min }
  end

  def session_anchor_date(window_start_at, start_m, end_m, crosses_midnight)
    return window_start_at.to_date unless crosses_midnight && end_m < start_m
    window_start_at.hour * 60 + window_start_at.min < end_m ? window_start_at.to_date - 1.day : window_start_at.to_date
  end

  def timeline_minutes_for(time, session_anchor, crosses_midnight)
    minutes = time.hour * 60 + time.min
    minutes += 1440 if crosses_midnight && time.to_date > session_anchor
    minutes
  end

  def parse_minutes(value)
    parts = value.to_s.split(":")
    return nil unless parts.length >= 2
    parts[0].to_i * 60 + parts[1].to_i
  end

  def block_days(block)
    raw_days = block["days"] || block[:days]
    values = case raw_days
    when String then raw_days.split(",").map(&:strip)
    else             Array(raw_days).map(&:to_s)
    end

    values.filter_map do |day|
      normalized = day.strip
      next if normalized.blank?
      Date::DAYNAMES.find { |name| name.casecmp?(normalized) } ||
        Date::DAYNAMES.find { |name| name[0, 3].casecmp?(normalized[0, 3]) }
    end
  end
end
