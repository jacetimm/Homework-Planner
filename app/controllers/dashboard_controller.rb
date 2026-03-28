class DashboardController < ApplicationController
  def index
    return unless current_user

    # Track unique-day visits
    @user_setting = UserSetting.for_user(current_user)
    unless @user_setting.last_visit_date == Date.current
      @user_setting.update_columns(
        visits_count:     @user_setting.visits_count.to_i + 1,
        first_visited_at: @user_setting.first_visited_at || Time.current,
        last_visit_date:  Date.current
      )
      @user_setting.reload
    end

    @onboarding = !@user_setting.onboarding_completed?

    if @onboarding
      begin
        @google_calendars = CalendarService.new(current_user.access_token).calendars
      rescue Google::Apis::AuthorizationError, Google::Apis::ClientError => e
        Rails.logger.warn("[DashboardController] Auth error fetching calendars for onboarding: #{e.message}")
        @google_calendars = []
      end
    end

    result = DashboardBuilder.new(current_user).call

    completed_sessions = StudySession.where(user_id: current_user.id).where.not(actual_minutes: nil).count
    @flags = FeatureFlags.new(user_setting: @user_setting, completed_sessions: completed_sessions)

    @detect_timezone         = session.delete(:detect_timezone)
    @courses                 = result.courses
    @schedule                = result.schedule
    @tonight_assignments     = result.tonight_assignments
    @tonight_summary         = result.tonight_summary
    @weekly_preview          = result.weekly_preview
    @danger_zone             = result.danger_zone
    @danger_zone_ids         = result.danger_zone_ids
    @streak                  = result.streak
    @calibration_nudges      = result.calibration_nudges
    @any_pending_estimates   = result.any_pending_estimates
    @syncing                 = result.syncing
    @classroom_auth_missing  = result.classroom_auth_missing
    @calendar_auth_missing   = result.calendar_auth_missing
  end

  def sync
    return redirect_to root_path unless current_user

    current_user.classroom_cache&.destroy
    current_user.calendar_cache&.destroy
    redirect_to root_path, notice: "Syncing with Google Classroom…"
  end
end
