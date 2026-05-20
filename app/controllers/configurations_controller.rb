class ConfigurationsController < ApplicationController
  def ios_v1
    render json: {
      settings: {},
      rules: [
        {
          patterns: %w[/ /session/new /session/sso /auth_tokens/validations/new],
          properties: {
            presentation: "replace_root"
          }
        }
      ]
    }
  end
end
