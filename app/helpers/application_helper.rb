module ApplicationHelper
  # Converts minutes-from-midnight (e.g. 900 = 3:00 PM, 1500 = 1:00 AM) to "3:00 PM"
  def minutes_to_time(m)
    m = m % 1440
    h   = m / 60
    min = m % 60
    period = h >= 12 ? "PM" : "AM"
    h12 = h % 12
    h12 = 12 if h12.zero?
    "#{h12}:#{min.to_s.rjust(2, '0')} #{period}"
  end

  # Formats a minute count into human-readable time: "5h 29m", "1h", "45m"
  def format_minutes(m)
    m = m.to_i
    return "0m" if m <= 0
    h    = m / 60
    mins = m % 60
    if h > 0 && mins > 0
      "#{h}h #{mins}m"
    elsif h > 0
      "#{h}h"
    else
      "#{mins}m"
    end
  end
end
