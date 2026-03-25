class SyncClassroomJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    user_setting = UserSetting.for_user(user)
    service = ClassroomService.new(user.access_token, user_setting)
    courses = service.courses
    assignments = service.assignments

    cache = ClassroomCache.find_or_initialize_by(user_id: user.id)
    cache.store!(courses: courses, assignments: assignments)

    Rails.logger.info("[SyncClassroomJob] Refreshed classroom cache for user #{user_id}: #{courses.size} courses, #{assignments.size} assignments")
  rescue Google::Apis::AuthorizationError, Google::Apis::ClientError => e
    Rails.logger.warn("[SyncClassroomJob] Auth error for user #{user_id}: #{e.message}")
  rescue => e
    Rails.logger.error("[SyncClassroomJob] Failed for user #{user_id}: #{e.class} #{e.message}")
    raise
  end
end
