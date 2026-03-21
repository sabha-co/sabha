# frozen_string_literal: true

module Sabha
  module Saas
    class Engine < ::Rails::Engine
      # Non-isolated engine - we extend Sabha, not create a separate namespace
      # This means models like GlobalIdentity are accessible as ::GlobalIdentity

      engine_name "sabha_saas"

      # Disable automatic route loading - we define routes inline in initializer
      paths["config/routes.rb"] = []

      # Add SaaS paths to autoload
      initializer "sabha_saas.autoload_paths", before: :set_autoload_paths do |app|
        if Sabha.saas?
          app.config.autoload_paths << root.join("app/models")
          app.config.autoload_paths << root.join("app/controllers")
          app.config.autoload_paths << root.join("app/controllers/concerns")
          app.config.autoload_paths << root.join("app/helpers")
          app.config.autoload_paths << root.join("app/mailers")
          app.config.autoload_paths << root.join("app/channels/concerns")
          app.config.autoload_paths << root.join("app/jobs")
        end
      end

      # Add SaaS stylesheets to asset paths
      initializer "sabha_saas.assets" do |app|
        if Sabha.saas?
          app.config.assets.paths << root.join("app/assets/stylesheets")
        end
      end

      # Add SaaS views to view paths (for partials like workspace_selector)
      initializer "sabha_saas.view_paths", before: :add_view_paths do |app|
        if Sabha.saas?
          app.config.paths["app/views"].unshift(root.join("app/views").to_s)
        end
      end

      # Prepend SaaS routes to take precedence over core routes
      # These routes only match when OUTSIDE a workspace context (no tenant set)
      initializer "sabha_saas.routes", after: :add_routing_paths do |app|
        next unless Sabha.saas?

        app.routes.prepend do
          constraints(->(req) { ApplicationRecord.current_tenant.blank? }) do
            # Root - landing page with sign in/up (unauthenticated) or workspace selector (authenticated)
            root to: "saas/landing#show", as: :saas_root

            # Session (login/logout) - uses GlobalIdentity
            resource :session, only: [ :new, :create, :destroy ], controller: "saas/sessions"

            # Auth code OTP verification
            resource :auth_code, only: [ :show, :create ], controller: "saas/auth_codes"

            # Registration (signup) - creates new GlobalIdentity
            resource :registration, only: [ :new, :create ], controller: "saas/registrations"

            # Settings - edit GlobalIdentity + workspace list
            resource :settings, only: [ :show, :update ], controller: "saas/settings"

            # Workspace management
            resources :workspaces, only: [ :index, :new, :create, :show ], controller: "saas/workspaces"

            # Workspace membership management
            patch "workspace_memberships/reorder", to: "saas/workspace_memberships#reorder"

            # Platform admin area (superadmin only)
            namespace :admin do
              root to: "stats#show"
              resources :workspaces, only: [ :index, :show ] do
                resource :suspension, only: [ :create, :destroy ],
                         controller: "workspace_suspensions"
                resources :members, only: [ :index ], controller: "workspace_members"
                resources :backups, only: [ :index, :create ], controller: "workspace_backups" do
                  resource :restore, only: [ :create ], controller: "workspace_restores"
                end
              end
            end
          end
        end
      end

      # Detect misconfiguration: gem loaded but SaaS mode disabled
      initializer "sabha_saas.check_configuration", before: :load_config_initializers do
        if defined?(ActiveRecord::Tenanted) && !Sabha.saas?
          raise <<~ERROR
            \e[31m[Sabha] Configuration Error: activerecord-tenanted gem is loaded but SaaS mode is disabled.

            The Gemfile.saas was used (likely because tmp/saas.txt exists) but SAAS=false.

            To fix, choose one:
              • For SaaS mode: run with SAAS=true (or remove SAAS=false)
              • For self-host mode: rm tmp/saas.txt && bundle install && bin/dev
            \e[0m
          ERROR
        end
      end


      # Load SaaS initializers
      initializer "sabha_saas.load_initializers", after: :load_config_initializers do
        if Sabha.saas?
          Dir[root.join("config/initializers/**/*.rb")].sort.each do |initializer|
            load initializer
          end
        end
      end

      # Note: Untenanted migrations are configured in database.yml with migrations_paths
      # Do NOT add them to app.config.paths["db/migrate"] as that would cause them
      # to run on tenant databases as well.

      # Override authentication concern when SaaS enabled
      config.to_prepare do
        if Sabha.saas?
          # Load SaaS authentication concern which overrides core Authentication
          require_dependency Sabha::Saas::Engine.root.join("app/controllers/concerns/saas/authentication")
        end
      end

      # Include SaaS helpers in ActionController views
      initializer "sabha_saas.helpers" do
        ActiveSupport.on_load(:action_controller_base) do
          if Sabha.saas?
            helper WorkspaceSelectorHelper
            helper TenantingHelper
          end
        end
      end
    end
  end
end
