module HubHelper
  # Offer to keep this community in the member's sabha.co list. Only a
  # self-hosted install is a community sabha.co can list, and the Sabha apps
  # already show the list they got from sabha.co.
  def hub_list_prompt_offered?
    !Sabha.saas? && !Account.sso_auth? && Current.user && !Current.user.bot? &&
      Current.account&.settings&.suggest_hub_list? &&
      !platform.desktop_app? && !hotwire_native_app? &&
      !Current.user.hub_linked?
  end

  # "Continue with sabha.co" beside the community's own sign-in
  def hub_sign_in_offered?
    Sso::Provider.hub.configured?
  end

  def hub_list_nudge?
    hub_list_prompt_offered? && !Current.user.hub_list_prompt_dismissed?
  end

  # A plain link: sabha.co looks the community up and asks the member to
  # confirm. Nothing about the member travels with it.
  def hub_list_prompt_url
    "#{Sabha::HUB_URL}/remote_workspaces/new?#{{ origin: request.base_url, source: "prompt" }.to_query}"
  end

  def hub_name
    URI(Sabha::HUB_URL).host
  end
end
