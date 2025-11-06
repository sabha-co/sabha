module AllowBrowser
  extend ActiveSupport::Concern

  # Previously enforced browser version requirements - now disabled
  VERSIONS = { safari: 17.2, chrome: 120, firefox: 121, opera: 104, ie: false }

  # No browser checking is performed
  included do
    # Browser check has been disabled as requested
  end
end
