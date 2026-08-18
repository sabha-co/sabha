class ContentFilters::RemoveSoloUnfurledLinkText < ActionText::Content::Filter
  TWITTER_DOMAINS = %w[ x.com twitter.com ]
  TWITTER_DOMAIN_MAPPING = { "x.com" => "twitter.com" }

  def applicable?
    normalize_tweet_url(solo_unfurled_url) == normalize_tweet_url(content.to_plain_text)
  end

  def apply
    if lexxy_body?
      remove_link_paragraphs
    else
      remove_link_text_from_wrapping_div
    end
  end

  private
    def solo_unfurled_url
      ActionText::Attachment::OpengraphEmbed.from_node(unfurled_links.first)&.href if unfurled_links.size == 1
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

    # Lexxy wraps text in <p> paragraphs; legacy Trix bodies used a wrapping
    # <div> and <br>s. A <p> anywhere marks a Lexxy body — robust even when the
    # body also carries a legacy div[sgid] mention.
    def lexxy_body?
      fragment.find_all("p").any?
    end

    def remove_link_text_from_wrapping_div
      fragment.replace("div") { |node| node.tap { |n| n.inner_html = unfurled_links.first.to_s } }
    end

    def remove_link_paragraphs
      fragment.replace("p") do |node|
        node if node.at_css("action-text-attachment")
      end
    end
end
