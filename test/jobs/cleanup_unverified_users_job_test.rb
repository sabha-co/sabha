require "test_helper"

class CleanupUnverifiedUsersJobTest < ActiveJob::TestCase
  test "deletes unverified users older than 1 hour who never logged in" do
    # Create an old unverified user (should be deleted)
    old_unverified = User.create!(
      name: "Old Unverified",
      email_address: "old_unverified@example.com",
      created_at: 2.hours.ago
    )

    # Create a recent unverified user (should NOT be deleted)
    recent_unverified = User.create!(
      name: "Recent Unverified",
      email_address: "recent_unverified@example.com",
      created_at: 30.minutes.ago
    )

    # Create an old verified user (should NOT be deleted)
    old_verified = User.create!(
      name: "Old Verified",
      email_address: "old_verified@example.com",
      created_at: 2.hours.ago
    )
    old_verified.verify_email!

    # Create an old unverified user who has logged in (should NOT be deleted)
    old_authenticated = User.create!(
      name: "Old Authenticated",
      email_address: "old_authenticated@example.com",
      created_at: 2.hours.ago,
      last_authenticated_at: 1.hour.ago
    )

    CleanupUnverifiedUsersJob.perform_now

    # Old unverified user should be deleted
    assert_nil User.find_by(id: old_unverified.id)

    # Others should remain
    assert User.find_by(id: recent_unverified.id).present?
    assert User.find_by(id: old_verified.id).present?
    assert User.find_by(id: old_authenticated.id).present?
  end

  test "handles empty result set gracefully" do
    assert_nothing_raised do
      CleanupUnverifiedUsersJob.perform_now
    end
  end
end
