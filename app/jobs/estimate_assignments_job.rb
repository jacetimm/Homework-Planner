class EstimateAssignmentsJob < ApplicationJob
  queue_as :default

  # assignments_data: array of plain hashes with string keys:
  #   "course_work_id", "title", "description", "class_name"
  # access_token: optional Google OAuth token for Drive content extraction
  def perform(user_email, assignments_data, access_token = nil)
    estimator = TimeEstimator.new
    extractor = access_token.present? ? DriveContentExtractor.new(access_token) : nil

    assignments_data.each do |a|
      course_work_id = a["course_work_id"]

      # Skip only if a real (non-fallback) estimate already exists.
      existing = AssignmentEstimate.find_by(user_email: user_email, course_work_id: course_work_id)
      next if existing && !fallback_reasoning?(existing.reasoning)

      materials_metadata = Array(a["materials_metadata"])
      materials_metadata = extractor.enrich_materials(materials_metadata) if extractor&.respond_to?(:enrich_materials)

      result = estimator.estimate(
        title:             a["title"].to_s,
        description:       a["description"].to_s,
        class_name:        a["class_name"].to_s,
        materials_metadata: materials_metadata
      )

      # Don't cache another fallback — wait for a real estimate next time.
      next if fallback_reasoning?(result[:reasoning])

      metadata = {
        description:        a["description"].to_s.first(2000),
        materials_count:    a["materials_count"].to_i,
        materials_metadata: materials_metadata.presence,
        max_points:         a["max_points"].presence&.to_i,
        title:              a["title"].to_s.first(255),
        class_name:         a["class_name"].to_s.first(255),
        due_date:           a["due_date"].presence
      }

      if existing
        existing.update!({ estimated_minutes: result[:minutes], reasoning: result[:reasoning] }.merge(metadata))
      else
        AssignmentEstimate.create!(
          { user_email: user_email, course_work_id: course_work_id,
            estimated_minutes: result[:minutes], reasoning: result[:reasoning] }.merge(metadata)
        )
      end

      Rails.logger.info(
        "[EstimateAssignmentsJob] course_work_id=#{course_work_id} source=#{result[:source]} " \
        "minutes=#{result[:minutes]} reasoning=#{result[:reasoning]}"
      )
    rescue StandardError => e
      Rails.logger.error("[EstimateAssignmentsJob] Failed for #{course_work_id}: #{e.message}")
    end
  end

  private

  FALLBACK_PHRASES = [ "API error", "API key", "Parse error", "used default" ].freeze

  def fallback_reasoning?(reasoning)
    FALLBACK_PHRASES.any? { |phrase| reasoning.to_s.include?(phrase) }
  end
end
