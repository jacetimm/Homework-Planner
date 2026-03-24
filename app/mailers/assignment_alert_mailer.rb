class AssignmentAlertMailer < ApplicationMailer
  def urgent_reminder(user_email:, title:, course:, due_in_hours:, estimated_minutes:, crunch_url:)
    @title             = title
    @course            = course
    @due_in_hours      = due_in_hours
    @estimated_minutes = estimated_minutes
    @crunch_url        = crunch_url

    mail(
      to:      user_email,
      subject: "⚡ #{title} is due in #{due_in_hours}h — haven't started yet"
    )
  end
end
