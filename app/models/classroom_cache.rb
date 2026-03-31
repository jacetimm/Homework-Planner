class ClassroomCache < ApplicationRecord
  belongs_to :user

  CACHE_TTL = 5.minutes

  def fresh?
    synced_at.present? && synced_at > CACHE_TTL.ago
  end

  # Returns an array of simple objects responding to .name and .alternate_link
  def courses
    Array(courses_data).map { |c| CoursePresenter.new(c) }
  end

  # Returns an array of hashes with symbol keys (matching ClassroomService format)
  def assignments
    Array(assignments_data).map { |a| deep_sym(a) }
  end

  # Stores Google API course objects + assignment hashes into the cache
  def store!(courses:, assignments:)
    serialized_courses = courses.map do |c|
      { "id" => c.id.to_s, "name" => c.name.to_s, "alternate_link" => c.alternate_link.to_s }
    end
    # Assignments have symbol keys and may have nested hashes/arrays — serialize to strings
    serialized_assignments = assignments.map { |a| deep_str(a) }

    update!(
      courses_data: serialized_courses,
      assignments_data: serialized_assignments,
      synced_at: Time.current
    )
  end

  private

  def deep_sym(obj)
    case obj
    when Hash  then obj.transform_keys(&:to_sym).transform_values { |v| deep_sym(v) }
    when Array then obj.map { |v| deep_sym(v) }
    else obj
    end
  end

  def deep_str(obj)
    case obj
    when Hash  then obj.transform_keys(&:to_s).transform_values { |v| deep_str(v) }
    when Array then obj.map { |v| deep_str(v) }
    when Symbol then obj.to_s
    else obj
    end
  end

  # Minimal presenter so the view can call .name and .alternate_link
  CoursePresenter = Struct.new(:data) do
    def name          = data["name"].to_s
    def alternate_link = data["alternate_link"].to_s
  end
end
