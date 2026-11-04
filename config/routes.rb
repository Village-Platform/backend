Rails.application.routes.draw do
  # Health check for load balancers and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  # Opening the bare domain goes to the admin dashboard.
  root to: redirect("/admin")

  # Files of the "database" Active Storage service (signed URLs that expire).
  get "files/:encoded_key/*filename", to: "stored_files#show", as: :stored_file, format: false

  # Vercel Cron jobs (protected by CRON_SECRET).
  get "internal/cron/subscription_reminders", to: "internal/cron#subscription_reminders"

  # Public account-deletion page (the URL declared in Google Play's Data safety form).
  get  "account/delete", to: "account_deletions#new", as: :account_deletion
  post "account/delete", to: "account_deletions#create"

  # Admin dashboard (server-rendered, Arabic RTL) — super admins only.
  namespace :admin do
    get    "login",  to: "sessions#new",     as: :login
    post   "login",  to: "sessions#create"
    delete "logout", to: "sessions#destroy", as: :logout

    root "dashboard#show"

    patch "theme", to: "theme#update", as: :theme
    get "search", to: "search#index", as: :search
    resources :reviews, only: :index

    resources :subscriptions do
      member do
        get :screenshot
        patch :approve
        patch :reject
      end
    end
    resources :firms do
      member do
        patch :approve
        patch :reject
        patch :suspend
        patch :restore
        delete :destroy_fully
      end
    end
    resources :categories do
      member do
        patch :toggle
      end
    end
    resources :articles do
      member do
        patch :approve
        patch :reject
        patch :restore
        delete :destroy_fully
      end
    end
    resources :subscription_plans do
      member do
        patch :toggle
      end
    end
    resources :users do
      member do
        patch :restore
        delete :destroy_fully
      end
      resources :firms, only: %i[ create destroy ], controller: "user_firms"
    end
    resources :feature_flags, except: :show do
      patch :toggle, on: :member
    end
    resources :notifications, only: %i[ index show new create destroy ]
    resources :notification_campaigns, only: %i[ index show new create ] do
      patch :cancel, on: :member
    end
    resources :topics do
      resources :members, only: %i[ create destroy ], controller: "topic_members"
    end
    resources :devices
  end

  namespace :api do
    namespace :v1 do
      post "auth/register", to: "auth#register"
      post "auth/login",    to: "auth#login"
      post "auth/guest",    to: "auth#guest"

      resource :me, only: %i[show update destroy], controller: "me"

      resources :categories do
        get :icon, on: :member
        resources :firms, only: :index
      end
      # approve / reject: admins and super admins review submissions (Firms::Review, Articles::Review).
      resources :firms do
        member do
          patch :approve
          patch :reject
        end
      end
      resources :articles do
        member do
          patch :approve
          patch :reject
        end
      end

      get "payment_methods", to: "payment_methods#index"
      get "app_config", to: "app_config#show"
      resources :subscription_plans
      resources :subscriptions, only: %i[index show create] do
        get :payment_screenshot, on: :member
      end
      resources :notifications, only: :index do
        patch :read, on: :member
        patch :read_all, on: :collection
      end
      resources :devices, only: :update, param: :installation_id do
        post :detach, on: :member
        resources :topics, only: %i[ update destroy ], param: :key, controller: "device_topics"
      end
      resources :topics, only: :index

      namespace :admin do
        resources :users, only: %i[index update]
        resources :subscriptions, only: %i[index show] do
          member do
            get :payment_screenshot
            patch :approve
            patch :reject
          end
        end
      end
    end
  end
end
