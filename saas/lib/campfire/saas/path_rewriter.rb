# frozen_string_literal: true

module Campfire
  module Saas
    # Middleware that extracts workspace ID from path and rewrites for routing.
    #
    # When a request comes in like `/1000002/rooms/general`:
    # 1. Extracts the workspace ID (1000002)
    # 2. Moves it from PATH_INFO to SCRIPT_NAME
    # 3. Stashes it in env for TenantSelector to use
    # 4. Routes see `/rooms/general` and URL helpers generate `/1000002/rooms/general`
    #
    # Runs BEFORE TenantSelector so the tenant resolver can read the stashed ID.
    class PathRewriter
      PATH_INFO_MATCH = %r{\A(/(\d{7,}))(/.*)?\z}

      def initialize(app)
        @app = app
      end

      def call(env)
        request = ActionDispatch::Request.new(env)

        if request.path_info =~ PATH_INFO_MATCH
          script_name_prefix = $1  # /1000002
          workspace_id = $2        # 1000002
          remaining_path = $3 || "/"

          # Move workspace prefix to SCRIPT_NAME
          request.script_name = "#{request.script_name}#{script_name_prefix}"
          request.path_info = remaining_path

          # Stash for tenant resolver
          env["campfire.workspace_id"] = workspace_id
        end

        @app.call(env)
      end
    end
  end
end
