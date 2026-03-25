class AssignmentsController < ApplicationController
  def reestimate
    unless current_user
      redirect_to root_path and return
    end

    course_work_id = params[:course_work_id].to_s
    user_email = current_user.email
    used_for_assignment = AssignmentReestimate.where(user_email: user_email, course_work_id: course_work_id).count
    daily_remaining = AssignmentReestimate.remaining_today_for(user_email)

    if used_for_assignment >= AssignmentReestimate::ASSIGNMENT_LIMIT
      flash[:alert] = "Out of re-estimates. Use 'My est' to set it manually."
      redirect_back(fallback_location: root_path) and return
    end

    if daily_remaining <= 0
      flash[:alert] = "Out of re-estimates today. Use 'My est' to set it manually."
      redirect_back(fallback_location: root_path) and return
    end

    AssignmentReestimate.create!(course_work_id: course_work_id, user_email: user_email)

    # Delete the cached estimate so the next dashboard load re-runs Groq
    deleted = AssignmentEstimate.where(course_work_id: course_work_id, user_email: user_email).delete_all
    remaining_today = AssignmentReestimate.remaining_today_for(user_email)

    if deleted > 0
      flash[:notice] = "Re-estimating — #{remaining_today}/#{AssignmentReestimate::DAILY_LIMIT} left today."
    else
      flash[:notice] = "Re-estimate requested — #{remaining_today}/#{AssignmentReestimate::DAILY_LIMIT} left today."
    end

    redirect_back(fallback_location: root_path)
  end

  def set_estimate
    unless current_user
      redirect_to root_path and return
    end

    course_work_id = params[:course_work_id].to_s
    user_email = current_user.email
    minutes        = parse_duration_minutes(params[:minutes])

    if minutes > 0 && minutes <= 600
      AssignmentEstimate.upsert(
        {
          course_work_id:    course_work_id,
          user_email:        user_email,
          estimated_minutes: minutes,
          reasoning:         "Set manually by student"
        },
        unique_by: [ :course_work_id, :user_email ]
      )
      flash[:notice] = "Estimate updated to #{helpers.format_minutes(minutes)}."
    else
      flash[:alert] = "Please enter a duration like 3h 45m, 3:45, or 225."
    end

    redirect_back(fallback_location: root_path)
  end

  private

  def parse_duration_minutes(raw_value)
    value = raw_value.to_s.strip.downcase
    return 0 if value.blank?

    if value.match?(/\A\d+\z/)
      return value.to_i
    end

    if (match = value.match(/\A(\d+):(\d{1,2})\z/))
      hours = match[1].to_i
      mins = match[2].to_i
      return hours * 60 + mins if mins < 60
    end

    hours = value[/(\d+)\s*h/, 1].to_i
    mins  = value[/(\d+)\s*m/, 1].to_i
    return (hours * 60) + mins if hours.positive? || mins.positive?

    0
  end
end
