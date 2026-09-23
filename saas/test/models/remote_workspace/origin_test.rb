# frozen_string_literal: true

require_relative "../../test_helper"

class RemoteWorkspace::OriginTest < ActiveSupport::TestCase
  test "reduces an address to its canonical https origin" do
    assert_equal "https://chat.acme.org", normalize("https://chat.acme.org")
    assert_equal "https://chat.acme.org", normalize("chat.acme.org")
    assert_equal "https://chat.acme.org", normalize("HTTPS://Chat.ACME.org:443/rooms/1?x=1#top")
    assert_equal "https://chat.acme.org", normalize("  https://chat.acme.org./  ")
  end

  test "keeps a non-default port" do
    assert_equal "https://chat.acme.org:8443", normalize("https://chat.acme.org:8443/")
  end

  test "converts international hosts to punycode" do
    assert_equal "https://xn--bcher-kva.example", normalize("https://Bücher.example")
  end

  test "keeps www and the apex apart" do
    refute_equal normalize("www.acme.org"), normalize("acme.org")
  end

  test "refuses plain http outside development" do
    assert_raises(RemoteWorkspace::Origin::Invalid) { normalize("http://chat.acme.org") }
  end

  test "refuses things that aren't web addresses" do
    [ "", "   ", "ftp://chat.acme.org", "https://", "https://user:pass@chat.acme.org", "not a url at all" ].each do |input|
      assert_raises(RemoteWorkspace::Origin::Invalid, input.inspect) { normalize(input) }
    end
  end

  test "refuses sabha.co itself and names the workspace in a workspace address" do
    error = assert_raises(RemoteWorkspace::Origin::Hub) { normalize("https://#{Branding.app_host}") }
    assert_nil error.workspace_id

    error = assert_raises(RemoteWorkspace::Origin::Hub) { normalize("#{Branding.app_host}/1000121/rooms/3") }
    assert_equal "1000121", error.workspace_id
  end

  test "treats a subdomain of sabha.co as a self-hosted community" do
    assert_equal "https://acme.#{Branding.app_host}", normalize("acme.#{Branding.app_host}")
  end

  private
    def normalize(input)
      RemoteWorkspace::Origin.normalize(input)
    end
end
