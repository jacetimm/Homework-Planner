class DashboardController < ApplicationController
  def index
    return unless current_user

    result = DashboardBuilder.new(current_user).call

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
  end

  def sync
    return redirect_to root_path unless current_user

    current_user.classroom_cache&.destroy
    current_user.calendar_cache&.destroy
    redirect_to root_path, notice: "Syncing with Google Classroom…"
  end
end
