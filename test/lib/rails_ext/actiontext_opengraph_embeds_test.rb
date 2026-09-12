require "test_helper"

class ActionText::Attachment::OpengraphEmbedTest < ActiveSupport::TestCase
  test "keeps absolute http and https links and images" do
    embed = embed_from href: "http://example.com/page", url: "https://example.com/image.png"

    assert_kind_of ActionText::Attachment::OpengraphEmbed, embed
    assert_equal "http://example.com/page", embed.href
    assert_equal "https://example.com/image.png", embed.url
  end

  test "keeps the link but drops an image that isn't a web URL" do
    embed = embed_from href: "https://example.com/page", url: "javascript:alert(1)"

    assert_kind_of ActionText::Attachment::OpengraphEmbed, embed
    assert_equal "https://example.com/page", embed.href
    assert_nil embed.url
  end

  test "keeps a Lexxy embed serialized in its content markup" do
    embed = embed_from content: opengraph_content(href: "https://example.com/page", src: "https://example.com/image.png")

    assert_kind_of ActionText::Attachment::OpengraphEmbed, embed
    assert_equal "https://example.com/page", embed.href
    assert_equal "https://example.com/image.png", embed.url
  end

  test "drops a link and an image that aren't web URLs" do
    [ "javascript:alert(1)", "data:text/html,pwned", "vbscript:msgbox(1)", "//example.com/page",
      "/rooms/1", "rooms/1", "http://exa mple.com/ ",
      "https:/rooms/1", "https:rooms/1", "http:/rooms/1", "https://" ].each do |value|
      embed = embed_from href: value, url: value

      assert_nil embed.href, "expected #{value.inspect} to be dropped as a link"
      assert_nil embed.url, "expected #{value.inspect} to be dropped as an image"
    end
  end

  test "drops a link and an image on this Sabha's own host, however it is spelled" do
    Current.set request: ActionDispatch::TestRequest.create("HTTP_HOST" => "once.sabha.test") do
      [ "https://once.sabha.test/rooms/1", "http://once.sabha.test/rooms/1",
        "https://ONCE.Sabha.Test/rooms/1", "https://once.sabha.test./rooms/1",
        "https://%6fnce.sabha.test/rooms/1", "https://%77ww.example.com/x.png" ].each do |value|
        embed = embed_from href: value, url: value

        assert_nil embed.href, "expected #{value.inspect} to be dropped as a link"
        assert_nil embed.url, "expected #{value.inspect} to be dropped as an image"
      end

      embed = embed_from href: "https://example.com/page", url: "https://example.com/image.png"
      assert_equal "https://example.com/page", embed.href
      assert_equal "https://example.com/image.png", embed.url
    end
  end

  test "drops a link and an image on a bare address rather than a domain name" do
    [ "http://127.0.0.1/rooms/1", "http://2130706433/rooms/1", "http://0177.0.0.1/rooms/1",
      "http://0x7f.0.0.1/rooms/1", "http://1.2.3.0xff/rooms/1", "http://[::1]/rooms/1",
      "http://localhost/rooms/1", "https://203.0.113.10/image.png" ].each do |value|
      embed = embed_from href: value, url: value

      assert_nil embed.href, "expected #{value.inspect} to be dropped as a link"
      assert_nil embed.url, "expected #{value.inspect} to be dropped as an image"
    end
  end

  test "renders the title as plain text when the link is dropped" do
    html = render_embed href: "javascript:alert(1)", url: "data:image/svg+xml;base64,PHN2Zy8+"

    assert_no_match /javascript:/, html
    assert_no_match /data:/, html
    assert_no_match /<img/, html
    assert_no_match /<a /, html
    assert_match "Title", html
  end

  test "keeps an internationalized domain written in punycode" do
    embed = embed_from href: "https://xn--80aswg.xn--p1ai/page", url: "https://xn--80aswg.xn--p1ai/image.png"

    assert_equal "https://xn--80aswg.xn--p1ai/page", embed.href
    assert_equal "https://xn--80aswg.xn--p1ai/image.png", embed.url
  end

  test "renders the image and the link when both are web URLs" do
    html = render_embed href: "https://example.com/page", url: "https://example.com/image.png"

    assert_match %r{href="https://example\.com/page"}, html
    assert_match %r{<img src="https://example\.com/image\.png"}, html
  end

  test "renders the title and the description as text" do
    html = render_embed href: "https://example.com/page", url: "https://example.com/image.png",
      filename: "<b>Title</b>", caption: "<img src=x onerror=alert(1)>"

    assert_no_match /<b>Title/, html
    assert_no_match /<img src=x/, html
    assert_match "&lt;b&gt;Title&lt;/b&gt;", html
    assert_match "&lt;img src=x onerror=alert(1)&gt;", html
  end

  private
    def attachment_for(href: nil, url: nil, filename: "Title", caption: "Description", content: nil)
      attributes = if content
        %(content-type="#{ActionText::Attachment::OpengraphEmbed::OPENGRAPH_EMBED_CONTENT_TYPE}" content="#{CGI.escapeHTML(content)}")
      else
        %(content-type="#{ActionText::Attachment::OpengraphEmbed::OPENGRAPH_EMBED_CONTENT_TYPE}" ) +
          %(href="#{href}" url="#{url}" filename="#{filename}" caption="#{caption}")
      end
      html = %(<action-text-attachment #{attributes}></action-text-attachment>)
      node = ActionText::Fragment.wrap(html).find_all(ActionText::Attachment.tag_name).first

      ActionText::Attachment.from_node(node)
    end

    def embed_from(**attributes)
      attachment_for(**attributes).attachable
    end

    def opengraph_content(href:, src:)
      %(<div class="og-embed"><div class="og-embed__content"><div class="og-embed__title">) +
        %(<a href="#{href}">Title</a></div><div class="og-embed__description">Description</div></div>) +
        %(<div class="og-embed__image"><img src="#{src}"></div></div>)
    end

    def render_embed(**attributes)
      embed = embed_from(**attributes)

      ApplicationController.render partial: embed.to_partial_path, locals: { opengraph_embed: embed }
    end
end
