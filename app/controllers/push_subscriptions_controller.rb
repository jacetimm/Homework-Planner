class PushSubscriptionsController < ApplicationController
  before_action :require_login

  def create
    endpoint = params[:endpoint].to_s.strip
    return head :bad_request if endpoint.blank?

    sub = current_user.push_subscriptions.find_or_initialize_by(endpoint: endpoint)
    sub.assign_attributes(
      p256dh_key: params[:p256dh_key].to_s,
      auth_key:   params[:auth_key].to_s
    )

    if sub.save
      head :ok
    else
      head :unprocessable_entity
    end
  end

  def destroy
    current_user.push_subscriptions.find_by(endpoint: params[:endpoint].to_s)&.destroy
    head :ok
  end

  def unsubscribe
    current_user.push_subscriptions.find_by(endpoint: params[:endpoint].to_s.strip)&.destroy
    head :ok
  end

  private

  def require_login
    head :unauthorized unless current_user
  end
end
