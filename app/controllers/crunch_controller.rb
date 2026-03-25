class CrunchController < ApplicationController
  # GET /crunch/:course_work_id — direct link from notification email
  # Redirects to dashboard with ?open_crunch= so JS auto-opens the overlay.
  def show
    unless current_user
      session[:return_to] = crunch_show_url(course_work_id: params[:course_work_id])
      redirect_to "/auth/google_oauth2" and return
    end

    redirect_to root_path(open_crunch: params[:course_work_id])
  end

  # GET /crunch/:course_work_id/microtasks
  # Returns cached microtasks or generates fresh ones via Groq.
  def microtasks
    unless current_user
      render json: { error: "Not logged in" }, status: :unauthorized and return
    end

    estimate = AssignmentEstimate.find_by(
      course_work_id: params[:course_work_id],
      user_email: current_user.email
    )

    unless estimate
      render json: { error: "Assignment not found" }, status: :not_found and return
    end

    # Return cached microtasks if present
    if estimate.microtasks.present?
      render json: { microtasks: estimate.microtasks, cached: true } and return
    end

    # Generate via Groq — use stored metadata for maximum context
    tasks = MicrotaskGenerator.new.generate(
      title:              params[:title].to_s.presence || estimate.reasoning.to_s,
      class_name:         params[:class_name].to_s,
      description:        estimate.description.to_s,
      materials_count:    estimate.materials_count.to_i,
      materials_metadata: Array(estimate.materials_metadata),
      max_points:         estimate.max_points,
      estimated_minutes:  estimate.estimated_minutes,
      due_date:           params[:due_date].presence
    )

    if tasks.present?
      estimate.update_columns(microtasks: tasks)
      render json: { microtasks: tasks, cached: false }
    else
      fallback = fallback_tasks(params[:title].to_s, estimate.estimated_minutes)
      render json: { microtasks: fallback, cached: false, fallback: true }
    end
  end

  private

  def fallback_tasks(title, total_minutes)
    steps = [
      "Review assignment requirements",
      "Gather notes and materials",
      "Work through the main content",
      "Review and check your work"
    ]
    per_task = [ (total_minutes / steps.size.to_f).ceil, 5 ].max
    steps.map { |s| { "task" => s, "minutes" => per_task } }
  end
end
