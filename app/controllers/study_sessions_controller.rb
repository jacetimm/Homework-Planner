class StudySessionsController < ApplicationController
  # POST /study_sessions — called when the timer starts
  def create
    unless session[:access_token]
      render json: { error: "Not logged in" }, status: :unauthorized and return
    end

    p = params.require(:study_session).permit(:course_work_id, :assignment_title, :course_name, :estimated_minutes)

    ss = StudySession.create!(
      course_work_id:    p[:course_work_id].to_s,
      user_email:        session[:user_email].to_s,
      assignment_title:  p[:assignment_title].to_s,
      course_name:       p[:course_name].to_s,
      estimated_minutes: p[:estimated_minutes].to_i,
      started_at:        Time.current
    )

    UserSetting.for_email(session[:user_email]).record_study_day!

    render json: { id: ss.id }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # PATCH /study_sessions/:id — called when the timer stops
  def update
    unless session[:access_token]
      render json: { error: "Not logged in" }, status: :unauthorized and return
    end

    ss = StudySession.find_by(id: params[:id], user_email: session[:user_email])
    unless ss
      render json: { error: "Session not found" }, status: :not_found and return
    end

    actual = params.require(:study_session).permit(:actual_minutes)[:actual_minutes].to_i
    ss.update!(actual_minutes: actual > 0 ? actual : 1)

    render json: { ok: true, actual_minutes: ss.actual_minutes, estimated_minutes: ss.estimated_minutes }
  end
end
