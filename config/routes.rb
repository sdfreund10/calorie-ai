Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", :as => :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root to: redirect { "/log/today" }

  get "log/:date", to: "logs#show", as: :daily_log
  get "log/:date/entries/new", to: "calorie_entries#new", as: :new_log_entry
  get "log/:date/entries/:id/edit", to: "calorie_entries#edit", as: :edit_log_calorie_entry
  get "log/:date/entries/:id", to: "calorie_entries#show", as: :log_calorie_entry
  post "log/:date/entries", to: "calorie_entries#create", as: :log_entries
  patch "log/:date/entries/:id", to: "calorie_entries#update", as: :log_entry
  delete "log/:date/entries/:id", to: "calorie_entries#destroy", as: :delete_log_calorie_entry
end
