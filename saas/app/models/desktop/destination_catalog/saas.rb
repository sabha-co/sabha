module Desktop
  class DestinationCatalog
    class Saas
      def initialize(request:)
        @request = request
      end

      def peers
        return [] unless Current.global_identity

        Current.global_identity.workspace_memberships_ordered.user_active.filter_map do |membership|
          workspace = membership.workspace
          next unless workspace&.active?

          {
            id: workspace.external_id.to_s,
            name: workspace.name,
            logo_url: logo_url_for(workspace),
            workspace_url: workspace_url_for(workspace),
            cable_url: cable_url_for(workspace)
          }
        end
      end

      private
        attr_reader :request

        def workspace_url_for(workspace)
          slug = workspace.slug.to_s.delete_prefix("/")
          "#{request.base_url}/#{slug}"
        end

        def cable_url_for(workspace)
          "#{request.base_url}/api/cable?wid=#{workspace.external_id}"
        end

        def logo_url_for(workspace)
          return unless workspace.has_logo?

          Rails.application.routes.url_helpers.account_logo_url(
            size: "small",
            host: request.host,
            protocol: request.protocol,
            script_name: workspace.slug
          )
        end
    end
  end
end
