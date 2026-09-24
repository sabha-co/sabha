# frozen_string_literal: true

require_relative "../../test_helper"

class RemoteWorkspace::PairableTest < ActiveSupport::TestCase
  SECRET = "acme-hub-secret"

  setup do
    @acme = remote_workspaces(:acme)
    @acme.update!(pairing_status: :active, paired_via: :self_serve, secret: SECRET, paired_by: global_identities(:alice))
  end

  test "finds the paired workspace a sign-in request comes from and checks its secret" do
    sso, sig = sign_in_request(SECRET)

    remote_workspace, payload = RemoteWorkspace.authenticate_sign_in(sso, sig)

    assert_equal @acme, remote_workspace
    assert_equal "workspace-nonce", payload.nonce
  end

  test "any other workspace's secret is refused" do
    sso, sig = sign_in_request("someone-elses-secret")

    assert_raises(Sso::Payload::InvalidSignature) { RemoteWorkspace.authenticate_sign_in(sso, sig) }
  end

  test "leaves requests for other return paths to the env clients" do
    sso, sig = sign_in_request(SECRET, return_sso_url: "https://chat.acme.org/session/sso/callback")

    assert_nil RemoteWorkspace.authenticate_sign_in(sso, sig)
  end

  test "refuses unknown and not yet paired workspaces before checking any signature" do
    Sso::Payload.expects(:decode).never

    sso, sig = sign_in_request(SECRET, return_sso_url: "https://unknown.example/session/hub/callback")
    assert_raises(RemoteWorkspace::NotPairedError) { RemoteWorkspace.authenticate_sign_in(sso, sig) }

    sso, sig = sign_in_request(SECRET, return_sso_url: "https://club.example/session/hub/callback")
    assert_raises(RemoteWorkspace::NotPairedError) { RemoteWorkspace.authenticate_sign_in(sso, sig) }
  end

  test "a disconnected workspace is told so" do
    @acme.disconnect!
    sso, sig = sign_in_request(SECRET)

    error = assert_raises(RemoteWorkspace::DisconnectedError) { RemoteWorkspace.authenticate_sign_in(sso, sig) }
    assert_equal @acme, error.remote_workspace
  end

  test "disconnecting keeps members' entries and forgets their approvals" do
    global_identities(:alice).consent_to_remote_workspace!(@acme)

    @acme.disconnect!

    assert @acme.reload.pairing_disconnected?
    assert_nil @acme.secret
    assert remote_workspace_memberships(:alice_acme).reload.present?
    assert_not global_identities(:alice).consented_to_remote_workspace?(@acme)
  end

  test "approving lists the workspace and remembers the approval" do
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

  test "the daily cleanup keeps paired workspaces and ones with waiting requests" do
    RemoteWorkspaceMembership.delete_all
    global_identities(:bob).request_remote_workspace_pairing!(remote_workspaces(:club))

    assert_empty RemoteWorkspace.abandoned

    RemoteWorkspacePairingRequest.delete_all
    @acme.disconnect!
    assert_equal [ @acme, remote_workspaces(:club) ].sort_by(&:id), RemoteWorkspace.abandoned.sort_by(&:id)
  end

  test "deleting an account forgets its requests and leaves its pairings working" do
    identity = global_identities(:charlie)
    @acme.update!(paired_by: identity)
    identity.request_remote_workspace_pairing!(remote_workspaces(:club))

    identity.destroy!

    assert_empty RemoteWorkspacePairingRequest.where(global_identity_id: identity.id)
    assert @acme.reload.pairing_active?
    assert_nil @acme.paired_by
  end

  test "a Cloud pairing retried from a stale copy gets the secret already issued" do
    club = remote_workspaces(:club)
    stale = RemoteWorkspace.find(club.id)

    issued = club.pair_sabha_cloud!.secret
    stale.pair_sabha_cloud!

    assert_equal issued, stale.secret
    assert_equal issued, club.reload.secret
  end

  private
    def sign_in_request(secret, return_sso_url: "https://chat.acme.org/session/hub/callback")
      Sso::Payload.encode({ nonce: "workspace-nonce", return_sso_url: return_sso_url }, secret)
    end
end
