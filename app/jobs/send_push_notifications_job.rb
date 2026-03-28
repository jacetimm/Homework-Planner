class SendPushNotificationsJob < ApplicationJob
  queue_as :default

  QUIET_END_HOUR     = 7   # Never send before 7 AM
  DEFAULT_QUIET_HOUR = 23  # Default quiet start (11 PM)
  DEFAULT_SEND_HOUR  = 18  # Default evening send window (6 PM)

  def perform
    now = Time.current
    User.includes(:user_setting, :push_subscriptions).find_each do |user|
      process_user(user, now)
    rescue StandardError => e
      Rails.logger.error("[SendPushNotificationsJob] user #{user.id}: #{e.message}")
    end
  end

  private

  def process_user(user, now)
    setting = user.user_setting
    return unless setting&.push_notifications_enabled
    return if user.push_subscriptions.empty?

    # Never send during quiet hours (study end time → 7 AM)
    return if quiet_hours?(now, setting)

    # Skip if student already opened the app today
    return if setting.last_visit_date == now.to_date

    # Max one notification per day
    return if already_notified_today?(user.email, now)

    notification = pick_notification(user.email, now, setting)
    return unless notification

    deliver(user, notification)
  end

  # Returns nil or a hash: { type:, title:, body:, path:, course_work_id: }
  def pick_notification(email, now, setting)
    today    = now.to_date
    tomorrow = today + 1

    unstarted = unstarted_estimates(email, [today, tomorrow])
    tonight   = unstarted.select { |e| e.due_date == today  && e.estimated_minutes >= 30 }
    tmrw      = unstarted.select { |e| e.due_date == tomorrow }

    # ── Trigger: due tonight, 30+ min ──────────────────────────────────────────
    # Approximate "3 hours before due" as: after 5 PM (most deadlines are 11:59 PM)
    if tonight.any? && now.hour >= 17
      best = tonight.max_by(&:estimated_minutes)
      mins = best.estimated_minutes
      return {
        type:          :tonight,
        title:         best.title.truncate(60),
        body:          "#{best.title.truncate(50)} due tonight · #{fmt(mins)}. Start now?",
        path:          "/crunch/#{best.course_work_id}",
        course_work_id: best.course_work_id
      }
    end

    # ── Evening window for tomorrow's work ─────────────────────────────────────
    return nil if now.hour < evening_send_hour(setting)
    return nil if tmrw.empty?

    total_mins = tmrw.sum(&:estimated_minutes)

    # ── Trigger: 2+ assignments tomorrow totaling 2+ hours ────────────────────
    if tmrw.size >= 2 && total_mins >= 120
      heaviest = tmrw.max_by(&:estimated_minutes)
      return {
        type:          :multi_tomorrow,
        title:         "#{tmrw.size} assignments due tomorrow",
        body:          "#{tmrw.size} assignments due tomorrow · #{fmt(total_mins)} total. Tap to see your plan.",
        path:          "/",
        course_work_id: heaviest.course_work_id  # for dedup record
      }
    end

    # ── Trigger: single assignment tomorrow, 1+ hour ──────────────────────────
    big = tmrw.select { |e| e.estimated_minutes >= 60 }.max_by(&:estimated_minutes)
    if big
      return {
        type:          :tomorrow,
        title:         big.title.truncate(60),
        body:          "#{big.title.truncate(45)} due tomorrow · #{fmt(big.estimated_minutes)} of work. Tap to start planning.",
        path:          "/crunch/#{big.course_work_id}",
        course_work_id: big.course_work_id
      }
    end

    nil
  end

  def unstarted_estimates(email, dates)
    AssignmentEstimate
      .where(user_email: email, due_date: dates)
      .where("estimated_minutes >= 1")
      .where.not(title: [nil, ""])
      .to_a
      .reject { |e| StudySession.exists?(user_email: email, course_work_id: e.course_work_id) }
  end

  def quiet_hours?(now, setting)
    quiet_start = setting.study_end_time&.hour || DEFAULT_QUIET_HOUR
    h = now.hour
    h >= quiet_start || h < QUIET_END_HOUR
  end

  # "2 hours into study window" or 6 PM by default
  def evening_send_hour(setting)
    if setting.study_start_time
      [setting.study_start_time.hour + 2, QUIET_END_HOUR].max
    else
      DEFAULT_SEND_HOUR
    end
  end

  def already_notified_today?(email, now)
    AssignmentAlert
      .where(user_email: email, alert_type: "daily_push")
      .where(sent_at: now.beginning_of_day..)
      .exists?
  end

  def fmt(mins)
    if mins >= 60
      h = mins / 60
      m = mins % 60
      m > 0 ? "~#{h}h #{m}m" : "~#{h}h"
    else
      "~#{mins} min"
    end
  end

  def deliver(user, notification)
    payload = {
      title: notification[:title],
      body:  notification[:body],
      path:  notification[:path]
    }

    sent = user.push_subscriptions.sum { |sub| push!(sub, payload) ? 1 : 0 }

    if sent > 0
      AssignmentAlert.create!(
        user_email:     user.email,
        user:           user,
        course_work_id: notification[:course_work_id],
        alert_type:     "daily_push",
        sent_at:        Time.current
      )
      Rails.logger.info(
        "[SendPushNotificationsJob] #{notification[:type]} → #{user.email}: #{notification[:body].truncate(80)}"
      )
    end
  end

  def push!(sub, payload)
    WebPush.payload_send(
      message:  payload.to_json,
      endpoint: sub.endpoint,
      p256dh:   sub.p256dh_key,
      auth:     sub.auth_key,
      vapid: {
        public_key:  Rails.application.credentials.dig(:vapid, :public_key),
        private_key: Rails.application.credentials.dig(:vapid, :private_key),
        subject:     "mailto:#{ENV.fetch('VAPID_CONTACT_EMAIL', 'admin@example.com')}"
      }
    )
    true
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
    sub.destroy
    false
  rescue StandardError => e
    Rails.logger.warn("[SendPushNotificationsJob] push failed for sub #{sub.id}: #{e.message}")
    false
  end
end
