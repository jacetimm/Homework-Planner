class HomeworkScheduler
  QUICK_TASK_THRESHOLD = 10

  def initialize(
    nightly_capacity: 120,
    tonight_capacity: nil,
    study_start_time: nil,
    study_end_time: nil,
    break_frequency: 45,
    break_duration: 10,
    extracurricular_blocks: [],
    hard_subjects: [],
    calendar_busy_blocks: [],
    max_per_subject: 45
  )
    @nightly_capacity       = nightly_capacity
    @tonight_capacity       = tonight_capacity || nightly_capacity
    @study_start_time       = study_start_time
    @study_end_time         = study_end_time
    @break_frequency        = break_frequency.to_i
    @break_duration         = break_duration.to_i
    @extracurricular_blocks = Array(extracurricular_blocks)
    @hard_subjects          = Array(hard_subjects)
    @calendar_busy_blocks   = Array(calendar_busy_blocks)
    @max_per_subject        = max_per_subject.to_i
  end

  def schedule(assignments)
    today = Date.current
    normalized_assignments = Array(assignments).filter_map do |assignment|
      next if assignment[:state] == "TURNED_IN" || assignment[:state] == "RETURNED"

      due_date = normalized_due_date(assignment[:due_date])
      if due_date
        assignment.merge(due_date: due_date)
      else
        # No due date — keep with a synthetic far-future date so urgency math works.
        # Will only get scheduled into leftover tonight capacity (urgency_score = 6).
        assignment.merge(due_date: today + 30.days, no_due_date: true)
      end
    end

    # 1. Initialize 7-day output
    schedule_hash = {}
    (0..6).each do |offset|
      date_str = (today + offset).to_s
      cap = offset == 0 ? @tonight_capacity : @nightly_capacity
      schedule_hash[date_str] = {
        total_minutes:      0,
        remaining_capacity: cap,
        assignments:        [],
        urgent:             [],
        needs_focus:        [],
        can_wait:           [],
        timeline:           []
      }
    end
    schedule_hash["busiest_day"] = nil
    schedule_hash["wont_fit"]    = []
    schedule_hash["wont_fit_tonight"] = []

    # 2. Filter to actionable assignments.
    # Dated assignments: due within 7 days.
    # No-due-date assignments: always eligible (scheduled into leftover capacity only).
    actionable = normalized_assignments.select do |a|
      a[:no_due_date] || (a[:due_date] - today).to_i <= 7
    end

    # 3. Score urgency
    actionable.each do |a|
      a[:estimated_minutes] ||= 30
      a[:urgency_score] = if a[:no_due_date]
        6 # lowest priority — only fills leftover capacity
      else
        days = (a[:due_date] - today).to_i
        case
        when days < 0  then 1
        when days == 0 then 2
        when days == 1 then 3
        when days == 2 then 4
        else 5
        end
      end
    end

    # 4. Sort: most urgent first, then longest
    sorted = actionable.sort_by { |a| [a[:urgency_score], -a[:estimated_minutes].to_i] }

    # 5. Schedule across available nights, respecting per-subject nightly cap
    sorted.each do |assignment|
      total_minutes  = assignment[:estimated_minutes].to_i
      minutes_left   = total_minutes
      due_date       = assignment[:due_date]
      days_until     = (due_date - today).to_i

      # No-due-date assignments only fill leftover capacity tonight — don't spread across the week.
      preferred_last_night = assignment[:no_due_date] ? today : (days_until <= 0 ? today : due_date - 1.day)
      fallback_last_night  = assignment[:no_due_date] ? today : (days_until <= 0 ? today : due_date)
      last_night           = preferred_last_night

      available_nights = [(last_night - today).to_i + 1, 1].max

      # Per-subject nightly cap — waived when due tonight/overdue, OR when there's
      # only one available night (splitting would just push work to the due date itself,
      # which is worse than doing it all in one sitting tonight).
      night_max = if @max_per_subject > 0 && days_until > 0 && available_nights > 1
        @max_per_subject
      else
        total_minutes
      end
      ideal_per_night  = (total_minutes.to_f / available_nights).ceil
      is_tight         = @max_per_subject > 0 && ideal_per_night > @max_per_subject

      added_entries, minutes_left = schedule_assignment(
        schedule_hash,
        assignment,
        total_minutes,
        days_until,
        night_max,
        today,
        last_night,
        false,
        is_tight,
        ideal_per_night
      )

      no_buffer_day = false
      if minutes_left > 0 && fallback_last_night > preferred_last_night
        added_entries, minutes_left = schedule_assignment(
          schedule_hash,
          assignment,
          total_minutes,
          days_until,
          night_max,
          preferred_last_night + 1.day,
          fallback_last_night,
          true,
          true,
          ideal_per_night,
          added_entries
        )
        no_buffer_day = added_entries.any? { |n| n[:entry][:no_buffer_day] }
      end

      # Overflow pass: if still unscheduled after the preferred + fallback windows,
      # push the remaining work into any available slot in the full 7-day window.
      # This ensures "Won't Fit Tonight" assignments still appear in the weekly workload.
      if minutes_left > 0
        overflow_start = [fallback_last_night + 1.day, today + 1.day].max
        if overflow_start <= today + 6.days
          added_entries, minutes_left = schedule_assignment(
            schedule_hash,
            assignment,
            total_minutes,
            days_until,
            total_minutes, # lift per-night cap — just get it onto the board
            overflow_start,
            today + 6.days,
            true,
            is_tight,
            ideal_per_night,
            added_entries
          )
          no_buffer_day = true if added_entries.any?
        end
      end

      # Attach the full night-by-night plan to every entry for this assignment
      # (shown as "Mon: 1h · Tue: 1h · Wed: 24m" on the card)
      if added_entries.size > 1
        split_plan = added_entries.map do |n|
          { day_abbr: n[:date].strftime("%a"), minutes: n[:entry][:minutes] }
        end
        added_entries.each { |n| n[:entry][:split_plan] = split_plan }
      end
      added_entries.each { |n| n[:entry][:no_buffer_day] = no_buffer_day if no_buffer_day }

      if minutes_left > 0
        schedule_hash["wont_fit"] << {
          title:                   assignment[:title],
          course:                  assignment[:class_name],
          minutes:                 minutes_left,
          full_assignment_minutes: total_minutes,
          due_date:                assignment[:due_date].to_s,
          assignment_link:         assignment[:assignment_link],
          course_work_id:          assignment[:course_work_id],
          urgency:                 days_until < 0 ? "overdue" : "upcoming",
          is_tight:                true,
          ideal_per_night:         ideal_per_night,
          no_buffer_day:           no_buffer_day
        }
      end
    end

    today_str = today.to_s

    # 6. Surface assignments that were fetched but did not get a slot tonight.
    populate_wont_fit_tonight!(schedule_hash, actionable, today)

    # 7. Classify today's assignments into priority buckets
    schedule_hash[today_str][:assignments].each do |a|
      priority = classify_priority(a)
      a[:priority] = priority.to_s
      schedule_hash[today_str][priority] << a
    end

    # 8. Build tonight's timeline
    if @study_start_time && @study_end_time
      schedule_hash[today_str][:timeline] =
        build_tonight_timeline(schedule_hash[today_str][:assignments])
    end

    # 9. Find busiest day
    max_min = -1
    (0..6).each do |offset|
      date_str = (today + offset).to_s
      m = schedule_hash[date_str][:total_minutes]
      if m > max_min
        max_min = m
        schedule_hash["busiest_day"] = date_str
      end
    end
    schedule_hash["busiest_day"] = nil if max_min == 0

    schedule_hash
  end

  private

  def normalized_due_date(value)
    return value if value.is_a?(Date)
    return Date.parse(value.to_s) if value.present?

    nil
  rescue ArgumentError
    nil
  end

  def populate_wont_fit_tonight!(schedule_hash, actionable, today)
    today_str = today.to_s
    tonight_ids = schedule_hash[today_str][:assignments].map { |entry| entry[:course_work_id].to_s }.uniq

    actionable.each do |assignment|
      next if assignment[:no_due_date] # no deadline — no urgency to surface in "won't fit tonight"
      course_work_id = assignment[:course_work_id].to_s
      next if tonight_ids.include?(course_work_id)

      weekly_entries = scheduled_entries_for(schedule_hash, course_work_id)
      weekly_minutes = weekly_entries.sum { |entry| entry[:minutes].to_i }
      total_minutes  = assignment[:estimated_minutes].to_i
      shortfall      = [total_minutes - weekly_minutes, 0].max
      first_night    = weekly_entries.min_by { |entry| entry[:date] }

      schedule_hash["wont_fit_tonight"] << {
        title: assignment[:title],
        course: assignment[:class_name],
        minutes: total_minutes,
        due_date: assignment[:due_date].to_s,
        assignment_link: assignment[:assignment_link],
        course_work_id: course_work_id,
        urgency: (assignment[:due_date] - today).to_i < 0 ? "overdue" : "upcoming",
        first_scheduled_date: first_night&.dig(:date)&.to_s,
        scheduled_minutes: weekly_minutes,
        shortfall_minutes: shortfall,
        reason: shortfall.positive? ? "No room before due date" : "Scheduled on a later night"
      }
    end
  end

  def scheduled_entries_for(schedule_hash, course_work_id)
    (0..6).flat_map do |offset|
      date = Date.current + offset
      Array(schedule_hash[date.to_s][:assignments]).filter_map do |entry|
        next unless entry[:course_work_id].to_s == course_work_id.to_s

        entry.merge(date: date)
      end
    end
  end

  def schedule_assignment(schedule_hash, assignment, total_minutes, days_until, night_max, start_day, end_day, no_buffer_day, is_tight, ideal_per_night, existing_entries = [])
    minutes_left = total_minutes - existing_entries.sum { |entry| entry[:entry][:minutes].to_i }
    added_entries = existing_entries.dup
    already_scheduled_dates = existing_entries.map { |e| e[:date] }.to_set

    d = start_day
    while d <= end_day && d <= Date.current + 6.days && minutes_left > 0
      day = schedule_hash[d.to_s]
      if day[:remaining_capacity] > 0 && !already_scheduled_dates.include?(d)
        normal_fitting = [minutes_left, day[:remaining_capacity], night_max].min
        # Use the full nightly budget (not just remaining_cap) as the absorb ceiling.
        # This prevents tiny day-splits when previous assignments have consumed some
        # remaining capacity but the full assignment still fits within one night's budget.
        fitting = absorb_split_if_tiny(
          total_minutes: minutes_left,
          split_minutes: normal_fitting,
          absorb_limit: @nightly_capacity
        )
        entry = {
          title:                   assignment[:title],
          course:                  assignment[:class_name],
          minutes:                 fitting,
          full_assignment_minutes: total_minutes,
          assignment_link:         assignment[:assignment_link],
          course_work_id:          assignment[:course_work_id],
          due_date:                assignment[:no_due_date] ? nil : assignment[:due_date].to_s,
          no_due_date:             assignment[:no_due_date] || false,
          urgency:                 days_until < 0 ? "overdue" : "upcoming",
          is_tight:                is_tight,
          ideal_per_night:         ideal_per_night,
          no_buffer_day:           no_buffer_day,
          estimate_source:         assignment[:estimate_source]
        }
        day[:assignments] << entry
        added_entries << { date: d, entry: entry }
        day[:remaining_capacity] = [day[:remaining_capacity] - fitting, 0].max
        day[:total_minutes]      += fitting
        minutes_left             -= fitting
      end
      d += 1.day
    end

    [added_entries, minutes_left]
  end

  def classify_priority(assignment)
    return :can_wait if assignment[:no_due_date]

    due_str    = assignment[:due_date]
    due_date   = due_str.is_a?(Date) ? due_str : Date.parse(due_str.to_s)
    days_until = (due_date - Date.current).to_i
    is_hard    = @hard_subjects.any? { |s| assignment[:course].to_s.downcase.include?(s.to_s.downcase) }
    is_long    = assignment[:full_assignment_minutes].to_i > 60

    if days_until <= 1 || assignment[:urgency] == "overdue"
      :urgent
    elsif days_until <= 2 || is_hard || is_long
      :needs_focus
    else
      :can_wait
    end
  end

  def build_tonight_timeline(assignments)
    now_m     = Time.current.hour * 60 + Time.current.min
    start_m   = @study_start_time.hour * 60 + @study_start_time.min
    raw_end_m = @study_end_time.hour * 60 + @study_end_time.min
    end_m     = raw_end_m < start_m ? raw_end_m + 1440 : raw_end_m

    # Normalize current time for midnight-crossover sessions
    adj_now   = (end_m > 1440 && now_m < raw_end_m) ? now_m + 1440 : now_m
    current_m = (adj_now >= start_m && adj_now < end_m) ? adj_now : start_m

    return [] if current_m >= end_m

    extra_blocks = today_busy_blocks(start_m, end_m).select { |b| b[:end_m] > current_m }
    queue        = assignments.map { |a| a.merge(minutes_left: a[:minutes].to_i) }
    timeline     = []
    study_accum  = 0

    loop do
      break if current_m >= end_m
      break if queue.empty? && extra_blocks.none? { |b| b[:start_m] >= current_m }

      # Consume any active extracurricular/calendar block
      active = extra_blocks.find { |b| b[:start_m] <= current_m && b[:end_m] > current_m }
      if active
        timeline << active.slice(:type, :start_m, :end_m, :label)
        current_m = active[:end_m]
        extra_blocks.delete(active)
        study_accum = 0
        next
      end

      break if queue.empty?

      # Insert break if due
      if @break_frequency > 0 && study_accum >= @break_frequency
        brk_end = [current_m + @break_duration, end_m].min
        timeline << { type: "break", start_m: current_m, end_m: brk_end, label: "Break" }
        current_m   = brk_end
        study_accum = 0
        next
      end

      # Calculate study block duration
      next_extra_m   = extra_blocks.map { |b| b[:start_m] }.select { |m| m > current_m }.min || end_m
      time_to_break  = @break_frequency > 0 ? (@break_frequency - study_accum) : Float::INFINITY
      available_study_minutes = [
        time_to_break.to_i,
        next_extra_m - current_m,
        end_m - current_m
      ].min

      if quick_task?(queue.first)
        quick_items, study_duration, quick_priority = consume_quick_tasks(queue, available_study_minutes)
        break if study_duration <= 0

        timeline << {
          type: "quick_tasks",
          start_m: current_m,
          end_m: current_m + study_duration,
          label: "Quick tasks (#{quick_items.size} item#{quick_items.size == 1 ? "" : "s"})",
          priority: quick_priority,
          items: quick_items
        }
        current_m   += study_duration
        study_accum += study_duration
        next
      end

      normal_study_duration = [queue.first[:minutes_left], available_study_minutes].min
      # Break boundaries are soft and can shift, but session end and busy blocks are hard stops.
      next_hard_boundary = [end_m - current_m, next_extra_m - current_m].min
      study_duration = absorb_split_if_tiny(
        total_minutes: queue.first[:minutes_left],
        split_minutes: normal_study_duration,
        absorb_limit: next_hard_boundary,
        check_stub:   true
      )

      break if study_duration <= 0

      a = queue.first
      timeline << {
        type:     "study",
        start_m:  current_m,
        end_m:    current_m + study_duration,
        label:    a[:title],
        course:   a[:course],
        priority: a[:priority] || "can_wait",
        link:     a[:assignment_link]
      }
      current_m        += study_duration
      study_accum      += study_duration
      a[:minutes_left] -= study_duration
      queue.shift if a[:minutes_left] <= 0
    end

    # Append any future extracurricular/calendar blocks not yet placed
    extra_blocks.select { |b| b[:start_m] >= current_m && b[:start_m] < end_m }.each do |b|
      timeline << b.slice(:type, :start_m, :end_m, :label)
    end

    timeline.sort_by { |b| b[:start_m] }
  end

  def quick_task?(assignment)
    assignment[:minutes_left].to_i.positive? && assignment[:minutes_left].to_i < QUICK_TASK_THRESHOLD
  end

  # Absorb the tiny leftover into the current block rather than creating a micro-split.
  # check_stub: true (timeline only) — also absorb when the PRE-split stub itself is
  # tiny (≤15 min), i.e. don't start an assignment when only a sliver fits before the
  # next break.  The scheduler passes check_stub: false so max_per_subject is respected.
  def absorb_split_if_tiny(total_minutes:, split_minutes:, absorb_limit:, check_stub: false)
    leftover = total_minutes - split_minutes
    can_absorb = leftover.positive? && total_minutes <= absorb_limit &&
                 (leftover <= 15 || (check_stub && split_minutes <= 15))
    can_absorb ? total_minutes : split_minutes
  end

  def consume_quick_tasks(queue, available_study_minutes)
    items = []
    duration = 0
    highest_priority = "can_wait"

    while queue.any? && quick_task?(queue.first)
      task_minutes = queue.first[:minutes_left].to_i
      break if duration + task_minutes > available_study_minutes

      task = queue.shift
      duration += task_minutes
      highest_priority = higher_priority(highest_priority, task[:priority] || "can_wait")
      items << {
        title: task[:title],
        course: task[:course],
        minutes: task_minutes,
        link: task[:assignment_link],
        priority: task[:priority] || "can_wait"
      }
    end

    [items, duration, highest_priority]
  end

  def higher_priority(left, right)
    priorities = { "urgent" => 0, "needs_focus" => 1, "can_wait" => 2 }
    priorities[right].to_i < priorities[left].to_i ? right : left
  end

  def today_busy_blocks(session_start_m, session_end_m)
    manual_blocks = today_extracurricular_blocks(session_start_m, session_end_m)
    calendar_blocks = @calendar_busy_blocks.filter_map do |b|
      start_m = b[:start_m].to_i
      end_m   = b[:end_m].to_i
      next unless start_m < session_end_m && end_m > session_start_m

      {
        type: "calendar",
        label: b[:label].to_s.presence || "Calendar Event",
        start_m: start_m,
        end_m: end_m
      }
    end

    (manual_blocks + calendar_blocks).sort_by { |b| b[:start_m] }
  end

  def today_extracurricular_blocks(session_start_m, session_end_m)
    today_name = Date.current.strftime("%A")
    @extracurricular_blocks.filter_map do |b|
      days = normalized_block_days(b["days"] || b[:days])
      next unless days.include?(today_name)

      st = (b["start_time"] || b[:start_time]).to_s
      et = (b["end_time"] || b[:end_time]).to_s
      next unless st.match?(/\d+:\d+/) && et.match?(/\d+:\d+/)

      sh, sm = st.split(":").map(&:to_i)
      eh, em = et.split(":").map(&:to_i)
      bs = sh * 60 + sm
      be = eh * 60 + em

      # Normalize for midnight crossover
      bs += 1440 if session_end_m > 1440 && bs < session_start_m
      be += 1440 if session_end_m > 1440 && be < session_start_m

      next unless bs < session_end_m && be > session_start_m

      {
        type: "extracurricular",
        label: (b["activity"] || b[:activity] || b["name"] || b[:name]).to_s,
        start_m: bs,
        end_m: be
      }
    end.sort_by { |b| b[:start_m] }
  end

  def normalized_block_days(raw_days)
    values = case raw_days
    when String
      raw_days.split(",").map(&:strip)
    else
      Array(raw_days).map(&:to_s)
    end

    values.filter_map do |day|
      normalized = day.strip
      next if normalized.blank?

      Date::DAYNAMES.find { |name| name.casecmp?(normalized) } ||
        Date::DAYNAMES.find { |name| name[0, 3].casecmp?(normalized[0, 3]) }
    end
  end
end
