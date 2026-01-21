module AccountsHelper
  def account_logo_tag(style: nil)
    link_to root_path do
      tag.figure image_tag(fresh_account_logo_path, alt: "Account logo", size: 300), class: "account-logo avatar #{style}"
    end
  end

  def online_users_count
    Membership.connected.select(:user_id).distinct.count
  end

  def badge_options
    badges = @badges || Badge.ordered
    [ [ "No badge", "" ] ] + badges.map { |b| [ b.name, b.id ] }
  end
end
