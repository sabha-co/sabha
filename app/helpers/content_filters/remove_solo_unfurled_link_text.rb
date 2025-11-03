class ContentFilters::RemoveSoloUnfurledLinkText < ActionText::Content::Filter
  def applicable?
    normalize_tweet_url(solo_unfurled_url) == normalize_tweet_url(content.to_plain_text)
  end

  def apply
    fragment.replace("div") { |node| node.tap { |n| n.inner_html = unfurled_links.first.to_s } }
  end

  private
    TWITTER_DOMAINS = %w[ x.com twitter.com ]
    TWITTER_DOMAIN_MAPPING = { "x.com" => "twitter.com" }

    def solo_unfurled_url
      unfurled_links.first["href"] if unfurled_links.size == 1
    end

    def unfurled_links
      fragment.find_all("action-text-attachment[@content-type='#{ActionText::Attachment::OpengraphEmbed::OPENGRAPH_EMBED_CONTENT_TYPE}']")
    end

    def normalize_tweet_url(url)
      return url unless twitter_url?(url)

      uri = URI.parse(url)

      uri.dup.tap do |u|
        u.host = TWITTER_DOMAIN_MAPPING[uri.host&.downcase] || uri.host
        u.query = nil
      end.to_s
    rescue URI::InvalidURIError
      url
    end

    def twitter_url?(url)
      url.present? && TWITTER_DOMAINS.any? { |domain| url.strip.include?(domain) }
    end
end
