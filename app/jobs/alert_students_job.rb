class AlertStudentsJob < ApplicationJob
  queue_as :default

  URGENT_HOURS       = 24
  MIN_ESTIMATE_MINS  = 30

  def perform
    now      = Time.current
    deadline = (now + URGENT_HOURS.hours).to_date

    # Pull every estimate that is due within 24 h and estimated ≥ 30 min
    AssignmentEstimate
      .where("due_date IS NOT NULL AND due_date <= ?", deadline)
      .where("estimated_minutes >= ?", MIN_ESTIMATE_MINS)
      .find_each do |estimate|

      next if estimate.due_date < Date.current  # already overdue — don't spam
      next if estimate.title.blank?

      user_email     = estimate.user_email
      course_work_id = estimate.course_work_id

      # Skip if alert already sent today
      next if AssignmentAlert.already_sent_today?(user_email: user_email, course_work_id: course_work_id)

      # Skip if any study session exists for this assignment
      next if StudySession.exists?(user_email: user_email, course_work_id: course_work_id)

      due_in_hours = ((estimate.due_date.end_of_day - now) / 1.hour).ceil.clamp(1, URGENT_HOURS)
      crunch_url   = crunch_url_for(course_work_id)

      AssignmentAlertMailer.urgent_reminder(
        user_email:        user_email,
        title:             estimate.title,
        course:            estimate.class_name.to_s,
        due_in_hours:      due_in_hours,
        estimated_minutes: estimate.estimated_minutes,
        crunch_url:        crunch_url
      ).deliver_later

      AssignmentAlert.record!(user_email: user_email, course_work_id: course_work_id)

    rescue StandardError => e
      Rails.logger.error("[AlertStudentsJob] #{estimate&.user_email}/#{estimate&.course_work_id}: #{e.message}")
    end
  end

  private

  def crunch_url_for(course_work_id)
    host = if Rails.env.production?
             ENV.fetch("APP_HOST") # fail loudly if missing in production
           else
             ENV.fetch("APP_HOST", "localhost:3000")
           end
    Rails.application.routes.url_helpers.crunch_show_url(
      course_work_id: course_work_id, host: host
    )
  rescue KeyError
    Rails.logger.error("[AlertStudentsJob] APP_HOST env var is not set — cannot generate email links")
    nil
  rescue StandardError
    nil
  end
end
