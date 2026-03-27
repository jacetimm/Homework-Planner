# Plain value object — no ActiveRecord.
# Pass user_setting and the number of completed study sessions.
class FeatureFlags
  def initialize(user_setting:, completed_sessions:)
    @s = user_setting
    @n = completed_sessions.to_i
  end

  def show_all?      = @s.show_all_features?

  # Always on
  def basic?         = true
  def priority_tabs? = true

  # 2nd visit
  def timeline?      = show_all? || @s.visits_count.to_i >= 2
  def reestimate?    = show_all? || @s.visits_count.to_i >= 2

  # 3 completed sessions
  def crunch_mode?   = show_all? || @n >= 3
  def split_view?    = show_all? || @n >= 3

  # First streak of 2+ days
  def streak?        = show_all? || @s.streak_count.to_i >= 2

  # 3rd visit
  def danger_zone?   = show_all? || @s.visits_count.to_i >= 3

  # 1 week of usage
  def calibration?   = show_all? || (@s.first_visited_at.present? && @s.first_visited_at <= 7.days.ago)

  # Show tooltip hints for first 3 visits
  def show_tooltips? = @s.visits_count.to_i <= 3
end
