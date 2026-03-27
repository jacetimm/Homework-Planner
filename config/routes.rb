Rails.application.routes.draw do
  resource :settings, only: [ :show, :update ]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Defines the root path route ("/")
  root "dashboard#index"
  post "/sync", to: "dashboard#sync", as: :sync_dashboard
  post "/onboarding/complete", to: "onboarding#complete", as: :complete_onboarding
  post "/assignments/:course_work_id/reestimate", to: "assignments#reestimate", as: :reestimate_assignment
  post "/assignments/:course_work_id/set_estimate", to: "assignments#set_estimate", as: :set_assignment_estimate
  resources :study_sessions, only: [ :create, :update ]
  get "/crunch/:course_work_id/microtasks", to: "crunch#microtasks", as: :crunch_microtasks
  get "/crunch/:course_work_id",            to: "crunch#show",      as: :crunch_show

  patch "/users/timezone", to: "users#set_timezone", as: :set_user_timezone

  get "/auth/google_oauth2/callback", to: "sessions#create"
  get "/auth/failure", to: "sessions#failure"
  delete "/logout", to: "sessions#destroy", as: :logout

  get "/privacy", to: "pages#privacy"
  get "/terms", to: "pages#terms"
end
