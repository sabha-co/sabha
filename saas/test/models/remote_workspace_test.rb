# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../../test/test_helpers/dns_test_helper"

class RemoteWorkspaceTest < ActiveSupport::TestCase
  include DnsTestHelper

  ORIGIN = "https://new.example"
  PNG = "\x89PNG\r\n\x1a\nlogo".b

  setup { stub_dns_resolution("93.184.216.34") }

  test "previews a new community from its manifest without saving it" do
    stub_manifest community: { name: "Acme", logo_url: "#{ORIGIN}/account/logo?size=small&v=1", url: ORIGIN }

    remote_workspace = RemoteWorkspace.preview("New.Example/rooms")

    assert remote_workspace.new_record?
    assert_equal ORIGIN, remote_workspace.origin
    assert_equal "Acme", remote_workspace.name
    assert_equal 1, remote_workspace.protocol_major
    assert_nil remote_workspace.alias_origin
  end

  test "previews an already listed community without fetching it again" do
    assert_equal remote_workspaces(:acme), RemoteWorkspace.preview("Chat.Acme.org")
    assert_not_requested :get, "https://chat.acme.org/api/manifest"
  end

  test "sends the protocol major and nothing about the person" do
    stub_manifest community: { name: "Acme" }

    RemoteWorkspace.preview(ORIGIN)

    assert_requested :get, "#{ORIGIN}/api/manifest", headers: { "Sabha-Protocol-Major" => "1" } do |request|
      request.headers.keys.none? { it.match?(/cookie|authorization/i) }
    end
  end

  test "falls back to the product name, then the host, for manifests without a community" do
    stub_manifest product: { name: "Acme Chat" }
    assert_equal "Acme Chat", RemoteWorkspace.preview(ORIGIN).name

    stub_manifest({})
    assert_equal "new.example", RemoteWorkspace.preview(ORIGIN).name
  end

  test "keeps a different public address as an alias hint only" do
    stub_manifest community: { name: "Acme", url: "https://chat.new.example" }
    assert_equal "https://chat.new.example", RemoteWorkspace.preview(ORIGIN).alias_origin

    [ "http://localhost", "https://localhost:3000", "https://10.0.0.5", "https://#{Branding.app_host}" ].each do |url|
      stub_manifest community: { name: "Acme", url: url }
      assert_nil RemoteWorkspace.preview(ORIGIN).alias_origin, url
    end
  end

  test "ignores a logo hosted anywhere but the community" do
    stub_manifest community: { name: "Acme", logo_url: "https://tracker.example/pixel.png" }

    assert_nil RemoteWorkspace.preview(ORIGIN).logo_source_url
  end

  test "tells an old or foreign server apart from an unreachable one" do
    stub_request(:get, "#{ORIGIN}/api/manifest").to_return(status: 404)
    assert_raises(RemoteWorkspace::Probe::NotSabha) { RemoteWorkspace.preview(ORIGIN) }

    stub_request(:get, "#{ORIGIN}/api/manifest").to_return(status: 200, body: "<html>", headers: { "Content-Type" => "text/html" })
    assert_raises(RemoteWorkspace::Probe::NotSabha) { RemoteWorkspace.preview(ORIGIN) }

    stub_request(:get, "#{ORIGIN}/api/manifest").to_return(status: 301, headers: { "Location" => "https://elsewhere.example/" })
    assert_raises(RemoteWorkspace::Probe::NotSabha) { RemoteWorkspace.preview(ORIGIN) }

    stub_request(:get, "#{ORIGIN}/api/manifest").to_return(status: 415)
    assert_raises(RemoteWorkspace::Probe::UnsupportedProtocol) { RemoteWorkspace.preview(ORIGIN) }

    stub_manifest protocol_major: 2
    assert_raises(RemoteWorkspace::Probe::UnsupportedProtocol) { RemoteWorkspace.preview(ORIGIN) }

    stub_request(:get, "#{ORIGIN}/api/manifest").to_return(status: 502)
    assert_raises(RemoteWorkspace::Probe::Unreachable) { RemoteWorkspace.preview(ORIGIN) }

    stub_request(:get, "#{ORIGIN}/api/manifest").to_timeout
    assert_raises(RemoteWorkspace::Probe::Unreachable) { RemoteWorkspace.preview(ORIGIN) }
  end

  test "refuses a host that resolves to a private address" do
    stub_dns_resolution("10.0.0.5")

    assert_raises(RemoteWorkspace::Probe::Unreachable) { RemoteWorkspace.preview(ORIGIN) }
    assert_not_requested :get, "#{ORIGIN}/api/manifest"
  end

  test "refuses an oversized manifest" do
    stub_request(:get, "#{ORIGIN}/api/manifest").to_return(status: 200, body: "x" * 65.kilobytes)

    assert_raises(RemoteWorkspace::Probe::Unreachable) { RemoteWorkspace.preview(ORIGIN) }
  end

  test "fetches the logo in the background after the first listing" do
    stub_manifest community: { name: "Acme", logo_url: "#{ORIGIN}/account/logo?v=1" }
    stub_request(:get, "#{ORIGIN}/account/logo?v=1").to_return(status: 200, body: PNG, headers: { "Content-Type" => "image/png" })

    remote_workspace = RemoteWorkspace.preview(ORIGIN)
    perform_enqueued_jobs { remote_workspace.save! }

    assert_equal PNG, remote_workspace.reload.logo_data
    assert_equal "image/png", remote_workspace.logo_content_type
  end

  test "keeps no logo that isn't a small image" do
    remote_workspace = RemoteWorkspace.create!(origin: ORIGIN, name: "New")
    stub_manifest community: { name: "Acme", logo_url: "#{ORIGIN}/account/logo?v=2" }

    stub_request(:get, "#{ORIGIN}/account/logo?v=2").to_return(status: 200, body: "<svg/>", headers: { "Content-Type" => "image/svg+xml" })
    remote_workspace.refresh
    assert_not remote_workspace.reload.logo?

    stub_request(:get, "#{ORIGIN}/account/logo?v=2").to_return(status: 200, body: "x" * 65.kilobytes, headers: { "Content-Type" => "image/png" })
    remote_workspace.refresh
    assert_not remote_workspace.reload.logo?
  end

  test "refreshing picks up a new name and clears the unreachable mark" do
    remote_workspace = RemoteWorkspace.create!(origin: ORIGIN, name: "New", unreachable_since: 3.days.ago)
    stub_manifest community: { name: "New Club" }

    remote_workspace.refresh

    assert_equal "New Club", remote_workspace.reload.name
    assert_nil remote_workspace.unreachable_since
    assert_not remote_workspace.unreachable?
  end

  test "a failed refresh keeps the last known name and reads as unreachable only after a day" do
    remote_workspace = RemoteWorkspace.create!(origin: ORIGIN, name: "New")
    stub_request(:get, "#{ORIGIN}/api/manifest").to_return(status: 503)

    remote_workspace.refresh
    assert_equal "New", remote_workspace.reload.name
    assert remote_workspace.unreachable_since.present?
    assert_not remote_workspace.unreachable?

    travel 1.day + 1.minute do
      remote_workspace.refresh
      assert remote_workspace.reload.unreachable?
    end
  end

  test "only communities somebody lists are kept" do
    unlisted = RemoteWorkspace.create!(origin: ORIGIN, name: "New")

    assert_equal [ unlisted ], RemoteWorkspace.abandoned
  end

  test "refreshes every community in the background" do
    assert_enqueued_jobs RemoteWorkspace.count, only: RemoteWorkspace::RefreshJob do
      RemoteWorkspace.refresh_all_later
    end
  end

  private
    def stub_manifest(overrides)
      body = { protocol_major: 1, product: { name: "Sabha" }, sign_in_path: "/session/new" }
      body = overrides.empty? ? { protocol_major: 1 } : body.merge(overrides)
      stub_request(:get, "#{ORIGIN}/api/manifest").to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end
end
