# frozen_string_literal: true

module Saas
  module WorkspaceSettings
    class ExportsController < ApplicationController
      before_action :ensure_administrator

      def show
      end

      def create
        unless Workspace::R2.configured?
          return redirect_to settings_export_path, alert: "Exports aren't configured. Ask the operator to set R2 credentials."
        end

        if (recent = Current.workspace.recent_export_request)
          return redirect_to settings_export_path,
            notice: "We've already sent an export to #{recent[:email]}. Check your inbox, or wait an hour to request another."
        end

        Current.workspace.record_export_request!(Current.user.email_address)
        Workspace::ExportJob.perform_later(Current.workspace, Current.user.email_address)
        redirect_to settings_export_path,
          notice: "We're preparing your export. We'll email a download link to #{Current.user.email_address} when it's ready."
      end
    end
  end
end
