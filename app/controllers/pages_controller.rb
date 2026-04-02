class PagesController < ApplicationController
  layout "landing", only: :home

  def home
    redirect_to dashboard_path if current_user
  end

  def privacy
  end

  def terms
  end
end
