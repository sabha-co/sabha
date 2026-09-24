# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../../test/test_helpers/dns_test_helper"

class RemoteWorkspacePairingTest < ActiveSupport::TestCase
  include DnsTestHelper

  setup do
    stub_dns_resolution("93.184.216.34")
    @acme = remote_workspaces(:acme)
  end

  test "starting a pairing gives the requester a fresh secret and leaves the workspace untouched" do
    pairing = global_identities(:alice).pair_remote_workspace!(@acme)

    assert_equal 64, pairing.secret.length
    assert_in_delta 24.hours.from_now, pairing.expires_at, 5.seconds
    assert @acme.reload.pairing_none?
    assert_nil @acme.hub_secret
  end

  test "the secret is encrypted at rest" do
    pairing = global_identities(:alice).pair_remote_workspace!(@acme)

    stored = RemoteWorkspacePairing.connection.select_value("SELECT secret FROM remote_workspace_pairings WHERE id = #{pairing.id}")
    assert_not_includes stored, pairing.secret
  end

  test "the first person to pair a new address creates its row" do
    stub_manifest("https://new.example", workspace: { name: "New" })

    assert_difference -> { RemoteWorkspace.count }, +1 do
      global_identities(:alice).pair_remote_workspace!(RemoteWorkspace.preview("new.example"))
    end
  end

  test "a host an env client answers for can't be paired" do
    with_env("SSO_PROVIDER_CLIENTS" => "cloud", "SSO_CLOUD_RETURN_HOST" => "chat.acme.org", "SSO_CLOUD_SECRET" => "s") do
      assert_raises(GlobalIdentity::RemoteWorkspaceClaimedError) do
        global_identities(:alice).pair_remote_workspace!(@acme)
      end
    end
  end

  test "verify pairs the workspace when its manifest carries the proof" do
    pairing = global_identities(:alice).pair_remote_workspace!(@acme)
    stub_manifest(@acme.origin, hub_proof: RemoteWorkspace.pairing_proof(pairing.secret, @acme.origin))

    pairing.verify!

    @acme.reload
    assert @acme.pairing_active?
    assert @acme.paired_via_self_serve?
    assert_equal pairing.secret, @acme.hub_secret
    assert_equal global_identities(:alice), @acme.paired_by
    assert_not RemoteWorkspacePairing.exists?(pairing.id)
  end

  test "verify refuses a manifest without the proof, or with someone else's" do
    pairing = global_identities(:alice).pair_remote_workspace!(@acme)

    stub_manifest(@acme.origin, {})
    assert_raises(RemoteWorkspacePairing::ProofMismatch) { pairing.verify! }

    stub_manifest(@acme.origin, hub_proof: RemoteWorkspace.pairing_proof("another-secret", @acme.origin))
    assert_raises(RemoteWorkspacePairing::ProofMismatch) { pairing.verify! }

    assert @acme.reload.pairing_none?
  end

  test "a proof made for another address doesn't pair this one" do
    pairing = global_identities(:alice).pair_remote_workspace!(@acme)
    stub_manifest(@acme.origin, hub_proof: RemoteWorkspace.pairing_proof(pairing.secret, "https://elsewhere.example"))

    assert_raises(RemoteWorkspacePairing::ProofMismatch) { pairing.verify! }
  end

  test "a squatter's waiting request doesn't stop the real admin" do
    global_identities(:bob).pair_remote_workspace!(@acme)
    admins = global_identities(:alice).pair_remote_workspace!(@acme)
    stub_manifest(@acme.origin, hub_proof: RemoteWorkspace.pairing_proof(admins.secret, @acme.origin))

    admins.verify!

    assert_equal admins.secret, @acme.reload.hub_secret
  end

  test "a newer verified pairing replaces the old one, so rotating and recovering work the same way" do
    first = global_identities(:alice).pair_remote_workspace!(@acme)
    stub_manifest(@acme.origin, hub_proof: RemoteWorkspace.pairing_proof(first.secret, @acme.origin))
    first.verify!

    second = global_identities(:bob).pair_remote_workspace!(@acme)
    stub_manifest(@acme.origin, hub_proof: RemoteWorkspace.pairing_proof(second.secret, @acme.origin))
    second.verify!

    @acme.reload
    assert_equal second.secret, @acme.hub_secret
    assert_equal global_identities(:bob), @acme.paired_by
  end

  test "requests expire after a day" do
    pairing = global_identities(:alice).pair_remote_workspace!(@acme)

    travel 25.hours do
      assert pairing.expired?
      assert_includes RemoteWorkspacePairing.expired, pairing
      assert_not_includes RemoteWorkspacePairing.pending, pairing
    end
  end

  private
    def stub_manifest(origin, overrides)
      body = { protocol_major: 1, product: { name: "Sabha" } }.merge(overrides)
      stub_request(:get, "#{origin}/api/manifest").to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    def with_env(values)
      original = values.keys.index_with { ENV[it] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
end
