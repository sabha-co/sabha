module Opengraph::Metadata::Fetching
  extend ActiveSupport::Concern

  module ClassMethods
    def from_url(url)
      document = fetch_document(url)
      attributes = document.opengraph_attributes
      new attributes.merge(url: valid_canonical_url(attributes[:url], url), image: valid_image_content_type(attributes[:image]))
    end

    private
      TWITTER_HOSTS = %w[ twitter.com www.twitter.com x.com www.x.com ]
      FX_TWITTER_HOST = "fxtwitter.com"
      ALLOWED_IMAGE_CONTENT_TYPES = %w[ image/jpeg image/png image/gif image/webp ]

      def fetch_document(untrusted_url)
        tweet_url?(untrusted_url) ? fetch_fxtwitter_document(untrusted_url) : fetch_non_fxtwitter_document(untrusted_url)
      end

      def fetch_fxtwitter_document(untrusted_url)
        fxtwitter_url = replace_twitter_domain_for_opengraph_support(untrusted_url)

        Opengraph::Location.new(fxtwitter_url).then do |location|
          # fxtwitter.com HTML response does not include character encoding, resulting in emojis and quotes not
          # being encoded properly.
          Opengraph::Document.new(location.read_html.force_encoding("UTF-8"))
        end
      end

      def fetch_non_fxtwitter_document(untrusted_url)
        Opengraph::Location.new(untrusted_url).then do |location|
          Opengraph::Document.new(location.read_html)
        end
      end

      def valid_canonical_url(url, fallback)
        Opengraph::Location.new(url).valid? ? url : fallback
      end

      def valid_image_content_type(image)
        return unless image.present?

        content_type = Opengraph::Location.new(URI.parse(image)).fetch_content_type&.split(";")&.first&.downcase
        content_type.in?(ALLOWED_IMAGE_CONTENT_TYPES) ? image : nil
      rescue => e
        Rails.logger.warn "Failed to fetch image content tpye: #{image} (#{e})"
        nil
      end

      # Twitter.com and X.com do not support Opengraph at the moment.
      # Piggybacking on fxtwitter.com allows us to have twitter unfurling
      # without relying on fxtwitter.com's future availability.
      def replace_twitter_domain_for_opengraph_support(url)
        uri = URI.parse(url)
        uri.host = FX_TWITTER_HOST if uri.host.in?(TWITTER_HOSTS)
        uri.to_s
      rescue URI::InvalidURIError
        nil
      end

      def tweet_url?(url)
        uri = URI.parse(url)
        uri.host.in?(TWITTER_HOSTS) && uri.path.present? && uri.path != "/"
      rescue URI::InvalidURIError
        nil
      end
  end
end
