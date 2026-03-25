class AssignmentEstimate < ApplicationRecord
  belongs_to :user, optional: true

  validates :course_work_id, presence: true
  validates :user_email,     presence: true
  validates :estimated_minutes, presence: true, numericality: { greater_than: 0 }
  validates :course_work_id, uniqueness: { scope: :user_email }

  FALLBACK_PHRASES = [ "API error", "API key", "Parse error", "used default" ].freeze

  def self.cached_minutes_for(user_email, course_work_ids)
    where(user_email: user_email, course_work_id: course_work_ids)
      .reject { |e| FALLBACK_PHRASES.any? { |p| e.reasoning.to_s.include?(p) } }
      .index_by(&:course_work_id)
  end

  def self.clear_microtasks(user_email, course_work_id)
    where(user_email: user_email, course_work_id: course_work_id)
      .update_all(microtasks: nil)
  end
end
