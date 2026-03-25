class StudySession < ApplicationRecord
  belongs_to :user, optional: true

  validates :course_work_id, :user_email, :assignment_title, presence: true

  scope :completed, -> { where.not(actual_minutes: nil) }

  # Per-course calibration factors based on actual vs. estimated time.
  # Returns { "Course Name" => factor } for courses with enough completed sessions.
  # Factor > 1.0 means the student consistently takes longer than estimated.
  def self.calibration_factors(email, min_sessions: 3)
    completed
      .where(user_email: email)
      .where.not(estimated_minutes: nil)
      .group(:course_name)
      .having("COUNT(*) >= #{min_sessions}")
      .select(:course_name, "SUM(actual_minutes) as sum_actual", "SUM(estimated_minutes) as sum_estimated")
      .each_with_object({}) do |row, h|
        next if row.sum_estimated.to_f <= 0

        factor = (row.sum_actual.to_f / row.sum_estimated.to_f).round(2)
        # Only apply upward adjustments (don't reduce if student is fast)
        h[row.course_name] = factor if factor > 1.1
      end
  end
end
