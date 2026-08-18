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

      # Workspace settings page
      resource :settings, only: [ :show ], controller: "saas/workspace_settings" do
        # Workspace database export (admin-only — for migrating to self-hosted)
        resource :export, only: [ :show, :create ], controller: "saas/workspace_settings/exports"
      end

      # Delete workspace (admin-only, confirmation-gated)
      resource :destruction, only: [ :create ], controller: "saas/workspace_destructions"

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
  get "/session/sso", to: "sso/handshakes#new", as: :sso_handshake
  get "/session/sso/callback", to: "sso/callbacks#show", as: :sso_callback
  get "/session/signed_out", to: "signed_out_sessions#show", as: :signed_out_session

  resources :auth_tokens, only: %i[create]
  namespace :auth_tokens do
    resource :validations, only: %i[new create]
  end
  get "auth_tokens/validate/:token", to: "auth_tokens/validations#create", as: :sign_in_with_token

  get "verify_email/:token", to: "email_verifications#show", as: :verify_email
  post "resend_verification", to: "email_verifications#resend", as: :resend_verification
  get "confirm_email_change/:token", to: "email_verifications#confirm_email_change", as: :confirm_email_change

  # Notification email unsubscribe — token is the tenant carrier, so no workspace prefix.
  # POST is the RFC 8058 one-click target; GET shows the confirmation page.
  get  "email/unsubscribe/:token", to: "email_unsubscribes#show",   as: :email_unsubscribe
  post "email/unsubscribe/:token", to: "email_unsubscribes#create"

  resources :password_resets, only: [ :new, :create, :edit, :update ], param: :token

  resource :account, only: %i[ show edit update ] do
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
          resources :rooms, only: %i[ index ], controller: "room_permissions" do
            resource :permission, only: %i[ show create update destroy ], controller: "room_permissions"
          end
        end
      end

      resource :bot_invite_code, only: :create, controller: "bot_invite_codes"

      resource :invitations, only: :show
      resource :permissions, only: :show
      resource :join_code, only: %i[ create update ]
      resource :logo, only: %i[ show destroy ]
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
        resource :appearance, only: :show
        resource :account_data, only: :show
        resource :avatar_shuffle, only: :create
        resource :email_change, only: :destroy
        resource :invite_link, only: :create
        resources :push_subscriptions do
          scope module: "push_subscriptions" do
            resources :test_notifications, only: :create
          end
        end
        resource :notification_settings, only: %i[ edit update ]
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
  post "join/:join_code", to: "api/bots/registrations#create", constraints: ->(req) { req.format.json? }, as: :join_bot

  get "join/:join_code", to: "users#new", as: :join
  post "join/:join_code", to: "users#create"

  namespace :rooms do
    get "browse", to: "browse#index", as: :browse
    resources :opens
    resources :closeds
    resources :forums do
      resources :posts, only: %i[ create edit update destroy ], module: "forums" do
        resource :solution, only: %i[ create destroy ], module: "posts"
      end
    end
    resources :directs
    # The thread panel (show) plus Follow, modeled as the current user's membership
    # on the thread: Follow = create, Unfollow = destroy (mirrors posts below).
    resources :threads, only: %i[ new create show edit update destroy ] do
      resource :membership, only: %i[ create destroy ], module: "threads"
    end

    # The in-app post panel (show) plus Follow, modeled as the current user's
    # membership on the post: Follow = create, Unfollow = destroy.
    resources :posts, only: :show do
      resource :membership, only: %i[ create destroy ], module: "posts"
    end
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
      resource :roster, only: :show
      resources :members, only: %i[ index create destroy ]
      resource :access, only: :update, controller: "access"
    end

    get "@:message_id", to: "rooms#show", as: :at_message
  end

  # Cable config discovery + JWT refresh. A signed-in client (browser, or a
  # native client once it authenticates) fetches its WebSocket URL and a fresh
  # identity token here instead of scraping the HTML meta tag — the refresh
  # sibling of the short-lived `jid` token minted into the layout.
  namespace :api, defaults: { format: :json } do
    resource :cable, only: :show
  end

  # Bot API — authenticate with `Authorization: Bearer <bot_key>`.
  namespace :api, defaults: { format: :json } do
    namespace :bots do
      resources :rooms, only: %i[ index create update destroy ] do
        resources :messages, only: %i[ index create ]
        resources :members, only: %i[ index create destroy ]
        resource  :membership, only: %i[ create destroy ]
      end

      resources :messages, only: %i[ show update destroy ] do
        resources :boosts, only: %i[ index create destroy ], module: :messages
      end

      resources :direct_messages, only: :create
      resource  :search,  only: :show
      resource  :profile, only: :update
      resources :users, only: %i[ index show ]
      namespace :autocompletable do
        resources :users, only: :index
      end
    end
  end

  resources :messages do
    scope module: "messages" do
      resources :boosts
      # Toggling a grouped reaction chip off deletes the current user's boost for
      # one emoji, addressed by content rather than id so any viewer can remove
      # their own.
      delete "boosts", to: "boosts#destroy", as: nil
      resource :bookmark, only: %i[ create destroy ]
    end
  end
  scope module: "messages" do
    resources :profiles, only: %i[show], as: :mention_profile
  end

  resource :inbox, only: %i[ show ] do
    scope module: "inboxes" do
      resources :activity, only: :index
      resources :direct_messages, only: :index
      resources :threads, only: :index
      resources :notifications, only: :index
      resources :messages, only: :index
      resources :bookmarks, only: :index
      resource  :clearance, only: :create
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

  get "/.well-known/change-password" => redirect(Sabha.saas? ? "/session/new" : "/password_resets/new")

  get "up" => "rails/health#show", as: :rails_health_check
end
