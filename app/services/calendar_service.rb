require "google/apis/calendar_v3"

class CalendarService
  # Read a user's calendar during a given window,
  # returning an array of busy blocks {start: Time, end: Time, label: String}.
  def initialize(access_token)
    @service = Google::Apis::CalendarV3::CalendarService.new
    @service.authorization = access_token
  end

  def calendars
    response = @service.list_calendar_lists

    Array(response.items).filter_map do |calendar|
      next if calendar.deleted

      {
        id: calendar.id.to_s,
        summary: calendar.summary.to_s,
        primary: !!calendar.primary,
        selected: calendar.selected != false
      }
    end
  rescue StandardError => e
    raise e if e.is_a?(Google::Apis::AuthorizationError) || (e.is_a?(Google::Apis::ClientError) && (e.status_code == 401 || e.message.to_s.include?("Unauthorized") || e.message.to_s.include?("Invalid Credentials")))
    Rails.logger.error("[Calendar] Failed to fetch calendar list: #{e.message}")
    []
  end

  def busy_blocks_between(start_time:, end_time:, ignored_keywords: [], ignored_calendar_ids: [], ignore_rules: [])
    return [] if start_time.blank? || end_time.blank? || start_time >= end_time

    ignored = Array(ignored_keywords).map { |keyword| keyword.to_s.strip.downcase }.reject(&:blank?)
    ignored_calendar_ids = Array(ignored_calendar_ids).map(&:to_s).reject(&:blank?)
    ignore_rules = normalize_ignore_rules(ignore_rules)
    window_start = start_time
    window_end = end_time

    Rails.logger.info(
      "[TimeDebug][Calendar] tz=#{Time.zone.name} " \
      "Time.now=#{Time.now} Time.current=#{Time.current} Time.zone.now=#{Time.zone.now} " \
      "Date.today=#{Date.today} Date.current=#{Date.current}"
    )

    blocks = []

    calendars.each do |calendar|
      next unless calendar[:selected]
      next if ignored_calendar_ids.include?(calendar[:id])

      response = @service.list_events(
        calendar[:id],
        single_events: true,
        order_by: "startTime",
        time_min: start_time.iso8601,
        time_max: end_time.iso8601
      )

      Array(response.items).each do |event|
        next if event.start.date_time.nil? || event.end.date_time.nil?
        next if event.transparency == "transparent"

        event_start = event.start.date_time.in_time_zone(Time.zone)
        event_end   = event.end.date_time.in_time_zone(Time.zone)
        summary     = event.summary.to_s.strip

        next if ignored.any? { |keyword| summary.downcase.include?(keyword) }
        next if ignore_rules.any? { |rule| ignore_rule_match?(rule, summary, calendar[:summary], calendar[:id]) }

        if event_end > event_start
          clamped_start = [ event_start, window_start, Time.current ].max
          clamped_end   = [ event_end, window_end ].min
          next if clamped_end <= clamped_start

          blocks << {
            start: clamped_start,
            end: clamped_end,
            label: summary.presence || "Calendar Event",
            calendar_id: calendar[:id],
            calendar_name: calendar[:summary],
            type: "calendar"
          }
        end
      end
    end

    blocks

  rescue StandardError => e
    raise e if e.is_a?(Google::Apis::AuthorizationError) || (e.is_a?(Google::Apis::ClientError) && (e.status_code == 401 || e.message.to_s.include?("Unauthorized") || e.message.to_s.include?("Invalid Credentials")))
    Rails.logger.error("[Calendar] Failed to fetch events: #{e.message}")
    []
  end

  private

  def normalize_ignore_rules(ignore_rules)
    Array(ignore_rules).filter_map do |rule|
      next unless rule.is_a?(Hash)

      keyword = rule["keyword"].to_s.strip.downcase
      next if keyword.blank?

      {
        keyword: keyword,
        calendar_id: rule["calendar_id"].to_s.strip
      }
    end
  end

  def ignore_rule_match?(rule, summary, calendar_name, calendar_id)
    keyword = rule[:keyword].to_s
    haystacks = [summary, calendar_name].map { |value| value.to_s.downcase }

    return false unless haystacks.any? { |value| value.include?(keyword) }
    return true if rule[:calendar_id].blank?

    rule[:calendar_id] == calendar_id.to_s
  end
end
