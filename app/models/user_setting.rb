class UserSetting < ApplicationRecord
  belongs_to :user, optional: true

  validates :user_email, presence: true, uniqueness: true
  validates :break_frequency, numericality: { only_integer: true, in: 5..240 }, allow_nil: true
  validates :break_duration,  numericality: { only_integer: true, in: 1..120 }, allow_nil: true
  validates :max_minutes_per_subject, numericality: { only_integer: true, in: 15..180 }, allow_nil: true
  validate  :study_window_valid

  after_initialize :set_defaults, if: :new_record?

  def calendar_ignored_keywords
    Array(self[:calendar_ignored_keywords])
  end

  def ignored_google_calendar_ids
    Array(self[:ignored_google_calendar_ids])
  end

  def calendar_ignore_rules
    Array(self[:calendar_ignore_rules]).filter_map do |rule|
      next unless rule.is_a?(Hash)

      {
        "keyword" => rule["keyword"].to_s,
        "calendar_id" => rule["calendar_id"].to_s
      }
    end
  end

  def block_google_calendar_events?
    !!self[:block_google_calendar_events]
  end

  # Primary: look up by user_id (FK). Falls back to email string for legacy data.
  def self.for_user(user)
    find_or_create_by(user_id: user.id) do |s|
      s.user_email = user.email
    end
  end

  # Legacy helper kept for background jobs that still pass an email string.
  def self.for_email(email)
    find_or_create_by(user_email: email)
  end

  # Call when a study session is started. Updates streak if this is a new day.
  def record_study_day!
    today = Date.current
    return if streak_last_date == today  # already counted today

    new_count = streak_last_date == today - 1 ? streak_count + 1 : 1
    update_columns(streak_count: new_count, streak_last_date: today)
  end

  def streak_active?
    streak_last_date.present? && streak_last_date >= Date.current - 1
  end

  private

  def study_window_valid
    return if study_start_time.blank? || study_end_time.blank?

    # end < start is valid — it means the session crosses midnight (e.g. 10 PM–2 AM)
    # only reject identical times (zero duration)
    if study_end_time == study_start_time
      errors.add(:study_end_time, "must be different from start time")
    end
  end

  def set_defaults
    # Defaults provided in requirements
    self.study_start_time ||= Time.parse("16:00:00") # 4:00 PM
    self.study_end_time ||= Time.parse("22:00:00")   # 10:00 PM
    self.break_frequency ||= 45
    self.break_duration ||= 10
    self.hard_subjects ||= []
    self.extracurricular_blocks ||= []
    self.block_google_calendar_events = true if self[:block_google_calendar_events].nil?
    self.calendar_ignored_keywords ||= []
    self.ignored_google_calendar_ids ||= []
    self.calendar_ignore_rules ||= []
    self.max_minutes_per_subject ||= 45
    self.onboarding_completed = false
  end
end
