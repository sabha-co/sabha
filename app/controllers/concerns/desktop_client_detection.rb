module DesktopClientDetection
  extend ActiveSupport::Concern

  DESKTOP_CLIENT_HEADER = "Sabha-Desktop-Client"

  included do
    helper_method :desktop_client? if respond_to?(:helper_method)
  end

  def desktop_client?
    request.headers[DESKTOP_CLIENT_HEADER].present?
  end
end
