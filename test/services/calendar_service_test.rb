require "test_helper"

class CalendarServiceTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  WINDOW_START = Time.zone.local(2026, 4, 13, 17, 0, 0)
  WINDOW_END   = Time.zone.local(2026, 4, 13, 22, 0, 0)

  setup do
    travel_to WINDOW_START
  end

  teardown { travel_back }

  def make_event(summary:, start_offset: 60, duration: 60, transparent: false)
    es = WINDOW_START + start_offset.minutes
    ee = es + duration.minutes
    OpenStruct.new(
      start:        OpenStruct.new(date_time: es),
      end:          OpenStruct.new(date_time: ee),
      transparency: transparent ? "transparent" : nil,
      summary:      summary
    )
  end

  def build_service_with_events(events, calendar_id: "cal_1", calendar_name: "My Calendar")
    fake_api = Object.new
    fake_api.define_singleton_method(:list_events) { |_, **| OpenStruct.new(items: events) }
    service = CalendarService.allocate
    service.instance_variable_set(:@service, fake_api)
    calendars = [{ id: calendar_id, summary: calendar_name, selected: true, primary: false }]
    [service, calendars]
  end

  # ── existing test ────────────────────────────────────────────────────────

  test "ignore rules match calendar names as well as event titles" do
    event = OpenStruct.new(
      start: OpenStruct.new(date_time: Time.zone.local(2026, 4, 13, 18, 0, 0)),
      end: OpenStruct.new(date_time: Time.zone.local(2026, 4, 13, 19, 0, 0)),
      transparency: nil,
      summary: "Team practice"
    )

    fake_api = Object.new
    fake_api.define_singleton_method(:list_events) do |_calendar_id, **|
      OpenStruct.new(items: [event])
    end

    service = CalendarService.allocate
    service.instance_variable_set(:@service, fake_api)

    service.stub(:calendars, [{ id: "calendar_n", summary: "N", selected: true, primary: false }]) do
      blocks = service.busy_blocks_between(
        start_time: Time.zone.local(2026, 4, 13, 17, 0, 0),
        end_time: Time.zone.local(2026, 4, 13, 22, 0, 0),
        ignore_rules: [{ "keyword" => "n", "calendar_id" => "" }]
      )

      assert_empty blocks
    end
  end

  # ── busy_blocks_between basics ───────────────────────────────────────────

  test "returns a block for a normal event within the window" do
    event = make_event(summary: "Study group", start_offset: 60, duration: 60)
    service, cals = build_service_with_events([event])

    service.stub(:calendars, cals) do
      blocks = service.busy_blocks_between(start_time: WINDOW_START, end_time: WINDOW_END)
      assert_equal 1, blocks.length
      assert_equal "Study group", blocks.first[:label]
    end
  end

  test "returns empty array when start_time equals end_time" do
    service, cals = build_service_with_events([])
    service.stub(:calendars, cals) do
      blocks = service.busy_blocks_between(start_time: WINDOW_START, end_time: WINDOW_START)
      assert_empty blocks
    end
  end

  test "returns empty array when start_time is after end_time" do
    service, cals = build_service_with_events([])
    service.stub(:calendars, cals) do
      blocks = service.busy_blocks_between(start_time: WINDOW_END, end_time: WINDOW_START)
      assert_empty blocks
    end
  end

  test "skips transparent (free) events" do
    event = make_event(summary: "Free time", transparent: true)
    service, cals = build_service_with_events([event])
    service.stub(:calendars, cals) do
      blocks = service.busy_blocks_between(start_time: WINDOW_START, end_time: WINDOW_END)
      assert_empty blocks
    end
  end

  test "skips events without date_time (all-day events)" do
    event = OpenStruct.new(
      start:        OpenStruct.new(date_time: nil),
      end:          OpenStruct.new(date_time: nil),
      transparency: nil,
      summary:      "Vacation"
    )
    service, cals = build_service_with_events([event])
    service.stub(:calendars, cals) do
      blocks = service.busy_blocks_between(start_time: WINDOW_START, end_time: WINDOW_END)
      assert_empty blocks
    end
  end

  test "ignores events matching ignored_keywords" do
    event = make_event(summary: "Lunch break")
    service, cals = build_service_with_events([event])
    service.stub(:calendars, cals) do
      blocks = service.busy_blocks_between(
        start_time:       WINDOW_START,
        end_time:         WINDOW_END,
        ignored_keywords: ["lunch"]
      )
      assert_empty blocks
    end
  end

  test "ignores events matching ignored_keywords case-insensitively" do
    event = make_event(summary: "LUNCH BREAK")
    service, cals = build_service_with_events([event])
    service.stub(:calendars, cals) do
      blocks = service.busy_blocks_between(
        start_time:       WINDOW_START,
        end_time:         WINDOW_END,
        ignored_keywords: ["lunch"]
      )
      assert_empty blocks
    end
  end

  test "skips calendars in ignored_calendar_ids" do
    event = make_event(summary: "Soccer practice")
    service, cals = build_service_with_events([event], calendar_id: "cal_sports")
    service.stub(:calendars, cals) do
      blocks = service.busy_blocks_between(
        start_time:           WINDOW_START,
        end_time:             WINDOW_END,
        ignored_calendar_ids: ["cal_sports"]
      )
      assert_empty blocks
    end
  end

  test "skips unselected calendars" do
    event = make_event(summary: "Board meeting")
    fake_api = Object.new
    fake_api.define_singleton_method(:list_events) { |_, **| OpenStruct.new(items: [event]) }
    service = CalendarService.allocate
    service.instance_variable_set(:@service, fake_api)
    cals = [{ id: "cal_unsel", summary: "Work", selected: false, primary: false }]
    service.stub(:calendars, cals) do
      blocks = service.busy_blocks_between(start_time: WINDOW_START, end_time: WINDOW_END)
      assert_empty blocks
    end
  end

  test "block includes calendar metadata" do
    event = make_event(summary: "Dentist")
    service, cals = build_service_with_events([event], calendar_id: "cal_personal", calendar_name: "Personal")
    service.stub(:calendars, cals) do
      blocks = service.busy_blocks_between(start_time: WINDOW_START, end_time: WINDOW_END)
      assert_equal "cal_personal", blocks.first[:calendar_id]
      assert_equal "Personal",     blocks.first[:calendar_name]
      assert_equal "calendar",     blocks.first[:type]
    end
  end

  test "ignore rule scoped to a specific calendar_id only matches that calendar" do
    event = make_event(summary: "Practice")
    service, cals = build_service_with_events([event], calendar_id: "cal_sports", calendar_name: "Sports")
    service.stub(:calendars, cals) do
      # Rule targets "cal_other" — should NOT block events on "cal_sports"
      blocks = service.busy_blocks_between(
        start_time:   WINDOW_START,
        end_time:     WINDOW_END,
        ignore_rules: [{ "keyword" => "practice", "calendar_id" => "cal_other" }]
      )
      assert_equal 1, blocks.length
    end
  end

  test "ignore rule with blank calendar_id matches any calendar" do
    event = make_event(summary: "Practice")
    service, cals = build_service_with_events([event], calendar_id: "cal_sports", calendar_name: "Sports")
    service.stub(:calendars, cals) do
      blocks = service.busy_blocks_between(
        start_time:   WINDOW_START,
        end_time:     WINDOW_END,
        ignore_rules: [{ "keyword" => "practice", "calendar_id" => "" }]
      )
      assert_empty blocks
    end
  end

  test "event label defaults to 'Calendar Event' when summary is blank" do
    event = OpenStruct.new(
      start:        OpenStruct.new(date_time: WINDOW_START + 60.minutes),
      end:          OpenStruct.new(date_time: WINDOW_START + 120.minutes),
      transparency: nil,
      summary:      ""
    )
    service, cals = build_service_with_events([event])
    service.stub(:calendars, cals) do
      blocks = service.busy_blocks_between(start_time: WINDOW_START, end_time: WINDOW_END)
      assert_equal "Calendar Event", blocks.first[:label]
    end
  end
end
