class SettingsController < ApplicationController
  before_action :require_login
  before_action :set_user_setting

  def show
    # Fetch active courses for the multi-select dropdown
    begin
      classroom_service = ClassroomService.new(current_user.access_token)
      @active_courses = classroom_service.courses
    rescue StandardError => e
      raise e if e.is_a?(Google::Apis::AuthorizationError) || (e.is_a?(Google::Apis::ClientError) && (e.status_code == 401 || e.message.to_s.include?("Unauthorized") || e.message.to_s.include?("Invalid Credentials")))
      Rails.logger.error "[Settings] Failed to fetch courses: #{e.message}"
      @active_courses = []
    end

    begin
      @google_calendars = CalendarService.new(current_user.access_token).calendars
    rescue StandardError => e
      raise e if e.is_a?(Google::Apis::AuthorizationError) || (e.is_a?(Google::Apis::ClientError) && (e.status_code == 401 || e.message.to_s.include?("Unauthorized") || e.message.to_s.include?("Invalid Credentials")))
      Rails.logger.error "[Settings] Failed to fetch calendars: #{e.message}"
      @google_calendars = []
    end

    # Pre-compute which calendar IDs are currently included so the view can highlight them
    @all_calendar_ids = @google_calendars.map { |c| c[:id] }
  end

  def update
    save_user_timezone

    if @user_setting.update(user_setting_params)
      redirect_to settings_path, notice: "Settings saved successfully."
    else
      redirect_to settings_path, alert: "Failed to save settings: #{@user_setting.errors.full_messages.join(', ')}"
    end
  end

  private

  def save_user_timezone
    tz_name = params[:timezone].to_s.strip
    return if tz_name.blank?
    as_zone = ActiveSupport::TimeZone[tz_name]
    current_user.update!(timezone: as_zone.name) if as_zone
  end

  def require_login
    unless current_user
      redirect_to root_path, alert: "You must be logged in to view settings."
    end
  end

  def set_user_setting
    @user_setting = UserSetting.for_user(current_user)
  end

  def user_setting_params
    # Convert 'hard_subjects' array properly from the form submission (multiple select)
    # Convert 'extracurricular_blocks' from the dynamic fields (if implemented as array of hashes)
    permitted = params.require(:user_setting).permit(
      :study_start_time,
      :study_end_time,
      :break_frequency,
      :break_duration,
      :max_minutes_per_subject,
      :block_google_calendar_events,
      included_google_calendar_ids: [],
      hard_subjects: []
    )

    # --- Calendar opt-in inversion ---
    # The form submits which calendars are INCLUDED. We need to store which are IGNORED.
    # Fetch all calendar IDs from Google and subtract the included set to get ignored set.
    included_ids = Array(permitted.delete(:included_google_calendar_ids)).reject(&:blank?)
    begin
      all_calendar_ids = CalendarService.new(current_user.access_token).calendars.map { |c| c[:id].to_s }
      # Any calendar whose ID is NOT in the included_ids list is ignored
      ignored_ids = all_calendar_ids - included_ids
    rescue StandardError => e
      Rails.logger.warn("[Settings] Could not fetch calendars to invert selection — preserving existing setting: #{e.message}")
      ignored_ids = @user_setting.ignored_google_calendar_ids # preserve existing if API call fails
    end
    permitted[:ignored_google_calendar_ids] = ignored_ids

    # Process extracurricular blocks — build explicit hashes instead of to_unsafe_h
    # so only the four known fields (activity, start_time, end_time, days) pass through.
    extracurricular_raw = params.dig(:user_setting, :extracurricular_blocks)
    if extracurricular_raw.present?
      permitted[:extracurricular_blocks] = extracurricular_raw.values.filter_map do |block|
        next if block[:activity].blank?
        {
          "activity"   => block[:activity].to_s,
          "start_time" => block[:start_time].to_s,
          "end_time"   => block[:end_time].to_s,
          "days"       => block[:days]
        }
      end
    else
      permitted[:extracurricular_blocks] = []
    end

    # Remove blank subjects from array (Rails multiple selects send an empty string first item)
    if permitted[:hard_subjects].present?
      permitted[:hard_subjects] = permitted[:hard_subjects].reject(&:blank?)
    else
      permitted[:hard_subjects] = []
    end

    # Same treatment for calendar ignore rules — only keyword and calendar_id pass through.
    rules_raw = params.dig(:user_setting, :calendar_ignore_rules)
    ignore_rules = if rules_raw.present?
      rules_raw.values.filter_map do |rule|
        keyword = rule[:keyword].to_s.strip.downcase
        next if keyword.blank?
        {
          "keyword"     => keyword,
          "calendar_id" => rule[:calendar_id].to_s
        }
      end
    else
      []
    end

    permitted[:ignored_google_calendar_ids] = Array(permitted[:ignored_google_calendar_ids]).reject(&:blank?)
    permitted[:calendar_ignore_rules] = ignore_rules
    permitted[:calendar_ignored_keywords] = ignore_rules.select { |rule| rule["calendar_id"].blank? }.map { |rule| rule["keyword"] }.uniq

    permitted
  end
end
