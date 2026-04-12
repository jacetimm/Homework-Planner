class OnboardingController < ApplicationController
  def complete
    return head :unauthorized unless current_user

    setting = UserSetting.for_user(current_user)

    setting.study_start_time = params[:study_start_time] if params[:study_start_time].present?
    setting.study_end_time   = params[:study_end_time]   if params[:study_end_time].present?

    if params[:break_frequency].present?
      val = params[:break_frequency].to_i
      setting.break_frequency = val if val.in?(5..240)
    end

    if params[:break_duration].present?
      val = params[:break_duration].to_i
      setting.break_duration = val if val.in?(1..120)
    end

    if params[:max_minutes_per_subject].present?
      val = params[:max_minutes_per_subject].to_i
      setting.max_minutes_per_subject = val if val.in?(15..180)
    end

    if params[:color_theme].present? && params[:color_theme].in?(%w[light dark auto])
      setting.color_theme = params[:color_theme]
    end

    if params[:show_all_features].present?
      setting.show_all_features = params[:show_all_features] == "1"
    end

    if params[:hard_subjects].present?
      setting.hard_subjects = Array(params[:hard_subjects]).reject(&:blank?)
    end

    extracurricular_raw = params[:extracurricular_blocks]
    if extracurricular_raw.present?
      setting.extracurricular_blocks = extracurricular_raw.values.filter_map do |block|
        next if block[:activity].blank?
        {
          "activity"   => block[:activity].to_s.strip,
          "start_time" => block[:start_time].to_s,
          "end_time"   => block[:end_time].to_s,
          "days"       => block[:days].to_s
        }
      end
    end

    if params.key?(:included_google_calendar_ids)
      included_ids = Array(params[:included_google_calendar_ids]).reject(&:blank?)
      begin
        all_calendar_ids = CalendarService.new(current_user.access_token).calendars.map { |c| c[:id].to_s }
        ignored_ids = all_calendar_ids - included_ids
        setting.ignored_google_calendar_ids = ignored_ids
        setting.block_google_calendar_events = included_ids.any?
      rescue StandardError => e
        Rails.logger.warn("[Onboarding] Could not fetch calendars to invert selection: #{e.message}")
      end
    end

    setting.onboarding_completed = true
    setting.save(validate: false)

    head :ok
  end
end
