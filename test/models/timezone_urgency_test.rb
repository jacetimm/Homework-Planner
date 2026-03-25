require "test_helper"

# Verifies that timezone-aware date calculations produce different urgency
# outcomes for users in different timezones at the same UTC moment.
#
# The scheduler computes urgency as `(due_date - Date.current).to_i`.
# With Time.zone set to the user's timezone, Date.current reflects their
# local date — so the same UTC wall-clock time can be "today" in one zone
# and "yesterday" (overdue) in another.
class TimezoneUrgencyTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  # 2026-03-25 01:00 UTC
  # Eastern (UTC-5): 2026-03-24 8:00 PM  → Date.current = March 24
  # Tokyo   (UTC+9): 2026-03-25 10:00 AM → Date.current = March 25
  UTC_MOMENT = Time.utc(2026, 3, 25, 1, 0, 0)
  DUE_DATE   = Date.new(2026, 3, 25)

  # ActiveSupport zone names used here (not IANA) — these are the values stored
  # in users.timezone and used with Time.use_zone throughout the app.
  EASTERN_ZONE = "Eastern Time (US & Canada)"
  # "Asia/Tokyo" maps to "Osaka" in ActiveSupport's zone list (same UTC+9 offset)
  TOKYO_ZONE   = "Osaka"

  test "Date.current differs between Eastern and Tokyo at the same UTC moment" do
    eastern_today = Time.use_zone(EASTERN_ZONE) do
      travel_to(UTC_MOMENT) { Date.current }
    end

    tokyo_today = Time.use_zone(TOKYO_ZONE) do
      travel_to(UTC_MOMENT) { Date.current }
    end

    assert_equal Date.new(2026, 3, 24), eastern_today,
      "Eastern user should still be on March 24 at 1 AM UTC"
    assert_equal Date.new(2026, 3, 25), tokyo_today,
      "Osaka/Tokyo user should already be on March 25 at 1 AM UTC"
  end

  test "assignment due March 25 shows different urgency for Eastern vs Tokyo" do
    # Eastern user: due_date is tomorrow (1 day away → urgent)
    eastern_days_left = Time.use_zone(EASTERN_ZONE) do
      travel_to(UTC_MOMENT) { (DUE_DATE - Date.current).to_i }
    end

    # Tokyo user: due_date is today (0 days left → urgent and due today)
    tokyo_days_left = Time.use_zone(TOKYO_ZONE) do
      travel_to(UTC_MOMENT) { (DUE_DATE - Date.current).to_i }
    end

    assert_equal 1, eastern_days_left,
      "Eastern user: 1 day until due — shows as urgent (tomorrow)"
    assert_equal 0, tokyo_days_left,
      "Tokyo user: due TODAY — shows as more urgent than Eastern user"
    assert tokyo_days_left < eastern_days_left,
      "Tokyo user should see higher urgency (fewer days left) than Eastern user"
  end

  test "assignment overdue in Tokyo is not yet overdue in Eastern at the same UTC moment" do
    # Assignment was due March 24. At 1 AM UTC on March 25:
    # Eastern: still March 24 → due TODAY (0 days left, not overdue)
    # Tokyo: already March 25 → due YESTERDAY (-1 days → overdue)
    yesterday_due = Date.new(2026, 3, 24)

    eastern_days_left = Time.use_zone(EASTERN_ZONE) do
      travel_to(UTC_MOMENT) { (yesterday_due - Date.current).to_i }
    end

    tokyo_days_left = Time.use_zone(TOKYO_ZONE) do
      travel_to(UTC_MOMENT) { (yesterday_due - Date.current).to_i }
    end

    assert_equal 0,  eastern_days_left, "Eastern: due today, not overdue yet"
    assert_equal(-1, tokyo_days_left,   "Tokyo/Osaka: already overdue by 1 day")
  end
end
