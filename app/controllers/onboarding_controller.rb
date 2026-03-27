class OnboardingController < ApplicationController
  def complete
    return head :unauthorized unless current_user

    setting = UserSetting.for_user(current_user)

    setting.study_start_time = params[:study_start_time] if params[:study_start_time].present?
    setting.study_end_time   = params[:study_end_time]   if params[:study_end_time].present?

    if params[:break_frequency].present?
      val = params[:break_frequency].to_i
      setting.break_frequency = val if val.in?(10..120)
    end

    if params[:break_duration].present?
      val = params[:break_duration].to_i
      setting.break_duration = val if val.in?(1..30)
    end

    if params[:max_minutes_per_subject].present?
      val = params[:max_minutes_per_subject].to_i
      setting.max_minutes_per_subject = val if val.in?(15..180)
    end

    if params[:show_all_features].present?
      setting.show_all_features = params[:show_all_features] == "1"
    end

    if params[:hard_subjects].present?
      setting.hard_subjects = Array(params[:hard_subjects]).reject(&:blank?)
    end

    setting.onboarding_completed = true
    setting.save(validate: false)

    head :ok
  end
end
