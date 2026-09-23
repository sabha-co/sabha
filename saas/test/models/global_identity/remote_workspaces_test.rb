# frozen_string_literal: true

require_relative "../../test_helper"

class GlobalIdentity::RemoteWorkspacesTest < ActiveSupport::TestCase
  setup { @alice = global_identities(:alice) }

  test "lists a community once, however often it's added" do
    again = @alice.list_remote_workspace!(remote_workspaces(:acme), source: :prompt)

    assert_equal remote_workspace_memberships(:alice_acme), again
    assert_equal "added", again.source
  end

  test "adding a hidden community shows it again" do
    remote_workspace_memberships(:alice_acme).update!(hidden: true)

    @alice.list_remote_workspace!(remote_workspaces(:acme), source: :added)

    assert_not remote_workspace_memberships(:alice_acme).reload.hidden
  end

  test "the first person to list an origin saves it, and later ones share the row" do
    @alice.list_remote_workspace!(RemoteWorkspace.new(origin: "https://new.example", name: "New"), source: :added)
    global_identities(:bob).list_remote_workspace!(RemoteWorkspace.new(origin: "https://new.example", name: "New (stale)"), source: :added)

    new_community = RemoteWorkspace.find_by!(origin: "https://new.example")
    assert_equal "New", new_community.name
    assert_equal 2, new_community.memberships.count
  end

  test "stops at the list limit" do
    fill_remote_workspace_list @alice

    assert_raises(GlobalIdentity::RemoteWorkspaceLimitReachedError) do
      @alice.list_remote_workspace!(remote_workspaces(:club), source: :added)
    end
    assert_nothing_raised { @alice.list_remote_workspace!(remote_workspaces(:acme), source: :added) }
  end

  test "the selector mixes workspaces and communities in one order, leaving out hidden ones" do
    club = @alice.list_remote_workspace!(remote_workspaces(:club), source: :added)
    club.update!(hidden: true)
    acme = remote_workspace_memberships(:alice_acme)

    assert @alice.reorder_switcher([ "1000003", "remote:#{acme.id}", "1000001" ])

    entries = @alice.switcher_memberships
    assert_equal [ "1000003", acme, "1000001" ], entries.map { it.is_a?(WorkspaceMembership) ? it.tenant : it }
  end

  test "reordering only touches the person's own entries" do
    @alice.reorder_switcher([ "remote:#{remote_workspace_memberships(:bob_acme).id}", "1000002" ])

    assert_nil remote_workspace_memberships(:bob_acme).reload.position
    assert_nil workspace_memberships(:bob_widgets).reload.position
  end

  test "reordering refuses anything but a list" do
    assert_not @alice.reorder_switcher(nil)
    assert_not @alice.reorder_switcher("1000001")
    assert_not @alice.reorder_switcher([])
  end

  test "forgetting a person's list keeps the communities others share" do
    @alice.remote_workspace_memberships.destroy_all

    assert RemoteWorkspace.exists?(remote_workspaces(:acme).id)
  end
end
