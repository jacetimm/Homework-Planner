class AssignmentAlert < ApplicationRecord
  validates :user_email, :course_work_id, :alert_type, :sent_at, presence: true

  def self.already_sent_today?(user_email:, course_work_id:, alert_type: "urgent_reminder")
    where(user_email: user_email, course_work_id: course_work_id, alert_type: alert_type)
      .where(sent_at: Time.current.beginning_of_day..)
      .exists?
  end

  def self.record!(user_email:, course_work_id:, alert_type: "urgent_reminder")
    create!(user_email: user_email, course_work_id: course_work_id,
            alert_type: alert_type, sent_at: Time.current)
  end
end
