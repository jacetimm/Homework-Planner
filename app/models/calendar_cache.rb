class CalendarCache < ApplicationRecord
  belongs_to :user

  CACHE_TTL = 15.minutes

  def fresh?
    synced_at.present? && synced_at > CACHE_TTL.ago
  end

  # Returns raw busy blocks: array of {start: Time, end: Time, label: String, calendar_name: String}
  def blocks
    Array(raw_blocks_data).map do |b|
      {
        start:         Time.zone.parse(b["start"].to_s),
        end:           Time.zone.parse(b["end"].to_s),
        label:         b["label"].to_s,
        calendar_name: b["calendar_name"].to_s
      }
    end
  end

  # Stores raw busy_blocks (array of {start: Time, end: Time, label:, calendar_name:})
  def store!(blocks:)
    serialized = Array(blocks).map do |b|
      {
        "start"         => b[:start]&.iso8601,
        "end"           => b[:end]&.iso8601,
        "label"         => b[:label].to_s,
        "calendar_name" => b[:calendar_name].to_s
      }
    end
    update!(raw_blocks_data: serialized, synced_at: Time.current)
  end
end
