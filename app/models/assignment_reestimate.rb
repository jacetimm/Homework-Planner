class AssignmentReestimate < ApplicationRecord
  belongs_to :user, optional: true

  ASSIGNMENT_LIMIT = 2
  DAILY_LIMIT = 10

  validates :course_work_id, presence: true
  validates :user_email, presence: true

  scope :for_user, ->(user_email) { where(user_email: user_email) }
  scope :for_day, ->(date) { where(created_at: date.beginning_of_day..date.end_of_day) }

  def self.daily_count_for(user_email, date: Time.zone.today)
    for_user(user_email).for_day(date).count
  end

  def self.remaining_today_for(user_email, date: Time.zone.today)
    [DAILY_LIMIT - daily_count_for(user_email, date: date), 0].max
  end

  def self.counts_by_assignment_for(user_email, course_work_ids)
    ids = Array(course_work_ids).map(&:to_s).reject(&:blank?)
    return {} if ids.empty?

    for_user(user_email).where(course_work_id: ids).group(:course_work_id).count
  end
end
