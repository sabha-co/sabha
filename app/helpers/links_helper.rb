require "uri"

module LinksHelper
  def friendly_domain(url)
    return if url.blank?

    url = "http://#{url}" unless url.match(/\Ahttp(s)?:\/\//)
    hostname = (URI.parse(url).hostname rescue url) || url
    hostname.sub(/^www\./, "")
  end

  def with_protocol(url)
    url.match(/\Ahttp(s)?:\/\//) ? url : "http://#{url}"
  end
end
