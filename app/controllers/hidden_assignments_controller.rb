class HiddenAssignmentsController < ApplicationController
  before_action :require_login

  def create
    @hidden_assignment = current_user.hidden_assignments.find_or_create_by(
      course_work_id: params[:course_work_id]
    ) do |ha|
      ha.course_name = params[:course_name]
      ha.assignment_title = params[:assignment_title]
      ha.hidden_at = Time.current
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path, notice: "Assignment hidden." }
    end
  end

  def destroy
    @hidden_assignment = current_user.hidden_assignments.find_by(course_work_id: params[:course_work_id])
    @hidden_assignment&.destroy

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to settings_path, notice: "Assignment unhidden." }
    end
  end
end
