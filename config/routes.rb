Rails.application.routes.draw do
  # Optional: Redirect www subdomain to root domain
  # Uncomment and configure for your domain if needed
  # constraints(host: /^www\.yourdomain\.com/) do
  #   match "(*any)", to: redirect { |params, request|
  #     "https://yourdomain.com/#{params[:any]}#{request.query_string.present? ? '?' + request.query_string : ''}"
  #   }, via: :all
  # end

  if Sabha.saas?
    # In SaaS mode, root only works inside workspace context (tenant set)
    constraints(->(req) { ApplicationRecord.current_tenant.present? }) do
      root to: "welcome#show"

      # Workspace settings page (view settings, delete workspace)
      resource :settings, only: [ :show, :destroy ], controller: "saas/workspace_settings"

      # Leave workspace (RESTful destroy on membership)
      resource :membership, only: [ :destroy ], controller: "saas/workspace_memberships"

      # Post-creation invite step
      resource :invite, only: :show, controller: "saas/workspace_invites"
    end
  else
    constraints(lambda { |req| req.session[:user_id].present? }) do
      root to: "welcome#show"
    end

    constraints(lambda { |req| req.session[:user_id].blank? }) do
      root to: redirect("/session/new"), as: :unauthenticated_root
    end
  end
  get "/chat", to: "welcome#show"

  resource :first_run

  resource :session do
    scope module: "sessions" do
      resources :transfers, only: %i[ show update ]
    end
  end

  resources :auth_tokens, only: %i[create]
  namespace :auth_tokens do
    resource :validations, only: %i[new create]
  end
  get "auth_tokens/validate/:token", to: "auth_tokens/validations#create", as: :sign_in_with_token

  get "verify_email/:token", to: "email_verifications#show", as: :verify_email
  post "resend_verification", to: "email_verifications#resend", as: :resend_verification
  get "confirm_email_change/:token", to: "email_verifications#confirm_email_change", as: :confirm_email_change

  resources :password_resets, only: [ :new, :create, :edit, :update ], param: :token

  resource :account do
    scope module: "accounts" do
      resources :users do
        resource :reactivation, only: :create, module: "users"
      end
      resources :badges, only: [ :index, :create, :update, :destroy ]

      resources :bots do
        scope module: "bots" do
          resource :key, only: :update
          resource :avatar, only: :destroy
          resource :avatar_shuffle, only: :create
          resources :rooms, only: [] do
            resource :permission, only: %i[ show create update destroy ], controller: "room_permissions"
          end
        end
      end

      resource :bot_invite_code, only: :create, controller: "bot_invite_codes"

      resource :join_code, only: :create
      resource :logo, only: %i[ show destroy ]
      resource :custom_styles, only: %i[ edit update ]
    end
  end

  direct :fresh_account_logo do |options|
    route_for :account_logo, v: Current.account&.updated_at&.to_fs(:number), size: options[:size]
  end

  resources :qr_code, only: :show

  resources :users, only: :show do
    scope module: "users" do
      resource :avatar, only: %i[ show destroy ]
      resource :ban, only: %i[ create destroy ]
      resources :messages, only: %i[ index ] do
        get :page, on: :collection
      end
      resources :searches, only: %i[ create ] do
        delete :clear, on: :collection
      end

      scope defaults: { user_id: "me" } do
        resource :sidebar, only: :show
        resources :hidden_rooms, only: :index
        resource :profile
        resource :avatar_shuffle, only: :create
        resource :email_change, only: :destroy
        resource :invite_link, only: :create
        resources :push_subscriptions do
          scope module: "push_subscriptions" do
            resources :test_notifications, only: :create
          end
        end
      end
    end
    resource :block, only: [ :create, :destroy ]
  end

  namespace :autocompletable do
    resources :users, only: :index
  end

  direct :fresh_user_avatar do |user, options|
    route_for :user_avatar, user.avatar_token, v: user.updated_at.to_fs(:number)
  end

  resource :skill, only: :show, controller: "skills"

  # Join routes for signup via invite link
  # Bot registration via invite URL (JSON) must come before human signup route
  post "join/:join_code", to: "bots/registrations#create", constraints: ->(req) { req.format.json? }, as: :join_bot

  get "join/:join_code", to: "users#new", as: :join
  post "join/:join_code", to: "users#create"

  namespace :rooms do
    get "browse", to: "browse#index", as: :browse
    resources :opens
    resources :closeds
    resources :directs
    resources :threads, only: %i[ create show edit update destroy ]
  end

  resources :rooms do
    resources :messages do
      resources :unreads, only: %i[ create ], module: "messages"
    end

    scope module: "rooms" do
      resource :refresh, only: :show
      resource :settings, only: :show
      resource :involvement, only: %i[ show update ] do
        get :notifications_ready, on: :member
      end
      resource :star, only: %i[ create destroy ]
      resource :membership, only: %i[ create destroy ]
      resources :members, only: %i[ index create destroy ]
      resource :access, only: :update, controller: "access"
    end

    get "@:message_id", to: "rooms#show", as: :at_message
  end

  # Bot API — authenticate with `Authorization: Bearer <bot_key>`.
  scope "/api/bots", as: :api_bots do
    resources :rooms, only: %i[ index create update destroy ], controller: "bots/rooms" do
      get    "messages",                        to: "messages/reads_by_bots#index",    as: :messages
      get    "messages/:id",                    to: "messages/reads_by_bots#show",     as: :message
      post   "messages",                        to: "messages/by_bots#create"
      patch  "messages/:id",                    to: "messages/by_bots#update"
      delete "messages/:id",                    to: "messages/by_bots#destroy"

      post   "messages/:message_id/thread",     to: "rooms/threads/by_bots#create",    as: :message_thread
      post   "messages/:message_id/boosts",     to: "messages/boosts/by_bots#create",  as: :message_boosts
      delete "messages/:message_id/boosts/:id", to: "messages/boosts/by_bots#destroy", as: :message_boost

      get    "members",                         to: "bots/members#index",              as: :members
      post   "members",                         to: "bots/members#create"
      delete "members/:user_id",                to: "bots/members#destroy",            as: :member

      post   "membership",                      to: "bots/memberships#create",         as: :membership
      delete "membership",                      to: "bots/memberships#destroy"
    end

    post  "direct_messages", to: "rooms/directs/by_bots#create", as: :direct_messages
    get   "search",          to: "bots/searches#index",          as: :search
    patch "profile",         to: "bots/profiles#update",         as: :profile
  end

  resources :messages do
    scope module: "messages" do
      resources :boosts
      resource :bookmark, only: %i[ create destroy ]
    end
  end
  scope module: "messages" do
    resources :profiles, only: %i[show], as: :mention_profile
  end

  resource :inbox, only: %i[ show ] do
    member do
      get :activity
      get :direct_messages
      get :threads
      get :notifications
      get :messages
      get :bookmarks
      post :clear
    end
    scope path: "/paged", as: :paged do
      resources :activity, only: %i[ index ], controller: "inboxes/activity"
      resources :direct_messages, only: %i[ index ], controller: "inboxes/direct_messages"
      resources :threads, only: %i[ index ], controller: "inboxes/threads"
      resources :notifications, only: %i[ index ], controller: "inboxes/notifications"
      resources :messages, only: %i[ index ], controller: "inboxes/messages"
      resources :bookmarks, only: %i[ index ], controller: "inboxes/bookmarks"
    end
  end

  resources :searches, only: %i[ index create ] do
    collection do
      delete :clear
      get :page
    end
  end


  resource :unfurl_link, only: :create

  resources :configurations, only: [] do
    get :ios_v1, on: :collection
  end

  get "webmanifest"    => "pwa#manifest"
  get "service-worker" => "pwa#service_worker"

  get "up" => "rails/health#show", as: :rails_health_check
end
