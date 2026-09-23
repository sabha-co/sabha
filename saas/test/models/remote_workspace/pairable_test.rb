# frozen_string_literal: true

require_relative "../../test_helper"

class RemoteWorkspace::PairableTest < ActiveSupport::TestCase
  SECRET = "acme-hub-secret"

  setup do
    @acme = remote_workspaces(:acme)
    @acme.update!(pairing_status: :active, paired_via: :self_serve, hub_secret: SECRET, paired_by: global_identities(:alice))
  end

  test "finds the paired community a sign-in request comes from and checks its secret" do
    sso, sig = sign_in_request(SECRET)

    remote_workspace, payload = RemoteWorkspace.authenticate_sign_in(sso, sig)

    assert_equal @acme, remote_workspace
    assert_equal "community-nonce", payload.nonce
  end

  test "any other community's secret is refused" do
    sso, sig = sign_in_request("someone-elses-secret")

    assert_raises(Sso::Payload::InvalidSignature) { RemoteWorkspace.authenticate_sign_in(sso, sig) }
  end

  test "leaves requests for other return paths to the env clients" do
    sso, sig = sign_in_request(SECRET, return_sso_url: "https://chat.acme.org/session/sso/callback")

    assert_nil RemoteWorkspace.authenticate_sign_in(sso, sig)
  end

  test "refuses unknown and not yet paired communities before checking any signature" do
    Sso::Payload.expects(:decode).never

    sso, sig = sign_in_request(SECRET, return_sso_url: "https://unknown.example/session/hub/callback")
    assert_raises(RemoteWorkspace::NotPaired) { RemoteWorkspace.authenticate_sign_in(sso, sig) }

    sso, sig = sign_in_request(SECRET, return_sso_url: "https://club.example/session/hub/callback")
    assert_raises(RemoteWorkspace::NotPaired) { RemoteWorkspace.authenticate_sign_in(sso, sig) }
  end

  test "a disconnected community is told so" do
    @acme.disconnect!
    sso, sig = sign_in_request(SECRET)

    error = assert_raises(RemoteWorkspace::Disconnected) { RemoteWorkspace.authenticate_sign_in(sso, sig) }
    assert_equal @acme, error.remote_workspace
  end

  test "disconnecting keeps members' entries and forgets their approvals" do
    global_identities(:alice).consent_to_remote_workspace!(@acme)

    @acme.disconnect!

    assert @acme.reload.pairing_revoked?
    assert_nil @acme.hub_secret
    assert remote_workspace_memberships(:alice_acme).reload.present?
    assert_not global_identities(:alice).consented_to_remote_workspace?(@acme)
  end

  test "approving lists the community and remembers the approval" do
    identity = global_identities(:unverified)

    identity.consent_to_remote_workspace!(@acme)

    membership = identity.remote_workspace_memberships.find_by!(remote_workspace: @acme)
    assert membership.shortcut?
    assert identity.consented_to_remote_workspace?(@acme)
  end

  test "signing in with the shortcut brings a hidden entry back" do
    remote_workspace_memberships(:alice_acme).update!(hidden: true)

    global_identities(:alice).signed_in_to_remote_workspace!(@acme)

    assert_not remote_workspace_memberships(:alice_acme).reload.hidden?
    assert @acme.reload.last_signed_in_at.present?
  end

  test "the daily cleanup keeps paired communities and ones with waiting requests" do
    RemoteWorkspaceMembership.delete_all
    global_identities(:bob).pair_remote_workspace!(remote_workspaces(:club))

    assert_empty RemoteWorkspace.abandoned

    RemoteWorkspacePairing.delete_all
    @acme.disconnect!
    assert_equal [ @acme, remote_workspaces(:club) ].sort_by(&:id), RemoteWorkspace.abandoned.sort_by(&:id)
  end

  test "deleting an account forgets its requests and leaves its pairings working" do
    identity = global_identities(:charlie)
    @acme.update!(paired_by: identity)
    identity.pair_remote_workspace!(remote_workspaces(:club))

    identity.destroy!

    assert_empty RemoteWorkspacePairing.where(global_identity_id: identity.id)
    assert @acme.reload.pairing_active?
    assert_nil @acme.paired_by
  end

  private
    def sign_in_request(secret, return_sso_url: "https://chat.acme.org/session/hub/callback")
      Sso::Payload.encode({ nonce: "community-nonce", return_sso_url: return_sso_url }, secret)
    end
end
