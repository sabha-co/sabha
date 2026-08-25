require "test_helper"

class User::PresenceTest < ActiveSupport::TestCase
  setup do
    @user = users(:david)
  end

  test "defaults to available" do
    assert_equal "available", User.new.availability
  end

  test "rejects an unknown state" do
    assert_raises(ArgumentError) { @user.availability = "on_holiday" }
  end

  # The ladder, one rung at a time. Each of these is a product rule someone
  # could reasonably argue the other way, so they're pinned individually.
  test "offline outranks whatever the user claimed" do
    @user.availability = :do_not_disturb
    assert_equal :offline, @user.presence_dot(connected: false, active: true)

    @user.availability = :available
    assert_equal :offline, @user.presence_dot(connected: false, active: true)
  end

  test "a manual state outranks inferred idleness" do
    @user.availability = :do_not_disturb
    assert_equal :dnd, @user.presence_dot(connected: true, active: false)

    @user.availability = :away
    assert_equal :away, @user.presence_dot(connected: true, active: false)
  end

  test "only available is second-guessed by idleness" do
    @user.availability = :available

    assert_equal :active, @user.presence_dot(connected: true, active: true)
    assert_equal :idle, @user.presence_dot(connected: true, active: false)
  end

  test "deactivated and banned users get no dot at all" do
    @user.status = :deactivated
    assert_nil @user.presence_dot(connected: true, active: true)

    @user.status = :banned
    assert_nil @user.presence_dot(connected: true, active: true)
  end

  test "own dot ignores liveness, since the viewer is demonstrably present" do
    @user.update! availability: :do_not_disturb, last_active_at: nil

    assert_equal :dnd, @user.own_presence_dot
  end

  # The dial in ACTIVITY_REFRESH_THRESHOLD is safe to turn, but only downward of
  # the window it feeds: if writes were rarer than the span that defines "active",
  # someone still typing would go amber mid-sentence while their tab sat inside
  # the throttle with nothing to report.
  test "a tab reporting on the slowest cadence the throttle allows never falls out of active" do
    @user.update! last_active_at: User::Presence::ACTIVITY_REFRESH_THRESHOLD.ago

    @user.interacted

    travel User::Presence::ACTIVITY_REFRESH_THRESHOLD do
      assert @user.reload.active_now?, "the next report is due now, and it's already too late"
    end
  end

  test "a busy tab does not hammer the writer" do
    @user.update! last_active_at: 10.seconds.ago
    before = @user.last_active_at

    @user.interacted

    assert_equal before.to_i, @user.reload.last_active_at.to_i
  end

  test "coming back after going quiet moves the dot for everyone" do
    @user.update! last_active_at: 30.minutes.ago

    assert_broadcasts broadcasting_for(Current.account, :presence), 1 do
      @user.interacted
    end

    assert @user.active_now?
  end

  test "staying active says nothing" do
    @user.update! last_active_at: 5.minutes.ago

    assert_no_broadcasts broadcasting_for(Current.account, :presence) do
      @user.interacted
    end

    assert @user.active_now?, "the watermark still advances, it just isn't news"
  end

  test "going idle ages the timestamp out rather than clearing it" do
    @user.update! last_active_at: Time.current

    assert_broadcasts broadcasting_for(Current.account, :presence), 1 do
      @user.went_idle
    end

    assert_not @user.active_now?
    assert @user.last_active_at.present?, "timestamp is the only idle signal; clearing it loses the edge"
  end

  test "going idle twice is not a second edge" do
    @user.update! last_active_at: Time.current
    @user.went_idle

    assert_no_broadcasts broadcasting_for(Current.account, :presence) do
      @user.went_idle
    end
  end

  test "changing presence announces it and counts as a sign of life" do
    @user.update! last_active_at: 30.minutes.ago

    assert_broadcasts broadcasting_for(Current.account, :presence), 1 do
      @user.change_availability! :do_not_disturb
    end

    assert_equal "do_not_disturb", @user.reload.availability
    assert @user.active_now?, "the chooser would otherwise be broadcast as idle"
  end

  test "re-picking the state you already hold says nothing" do
    @user.update! availability: :away, last_active_at: Time.current

    assert_no_broadcasts broadcasting_for(Current.account, :presence) do
      @user.change_availability! "away"
    end
  end

  test "an unknown state is refused" do
    assert_raises(ArgumentError) { @user.change_availability! "on_holiday" }
  end

  test "recent interaction alone proves reachability off-room" do
    @user.update! last_active_at: 1.minute.ago

    assert @user.connected_now?, "a page with no room subscription still reports interaction"
  end

  test "batch resolution matches the one-at-a-time answer" do
    users(:david).update! availability: :available, last_active_at: 1.minute.ago
    users(:jason).update! availability: :do_not_disturb, last_active_at: 30.minutes.ago

    dots = User.presence_dots_for [ users(:david), users(:jason) ]

    assert_equal :active, dots[users(:david).id]
    assert_equal :offline, dots[users(:jason).id], "idle and unwatched reads as offline"
  end

  test "batch resolution keeps a watched-but-quiet member idle rather than offline" do
    user = users(:jason)
    user.update! availability: :available, last_active_at: 30.minutes.ago
    user.memberships.first.update! connections: 1, connected_at: Time.current

    assert_equal :idle, User.presence_dots_for([ user ])[user.id]
  end
end
