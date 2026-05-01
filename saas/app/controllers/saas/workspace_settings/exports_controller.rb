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

        Workspace::ExportJob.perform_later(Current.workspace, Current.user.email_address)
        redirect_to settings_export_path,
          notice: "We're preparing your export. We'll email a download link to #{Current.user.email_address} when it's ready."
      end
    end
  end
end
