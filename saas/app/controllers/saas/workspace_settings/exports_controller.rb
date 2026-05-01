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

        Current.workspace.request_export!(Current.user.email_address)
        redirect_to settings_export_path,
          notice: "We're preparing your export. We'll email a download link to #{Current.user.email_address} when it's ready."
      rescue Workspace::ExportThrottled
        redirect_to settings_export_path,
          notice: "An export was already requested. Check your inbox for the download link, or try again shortly."
      end
    end
  end
end
