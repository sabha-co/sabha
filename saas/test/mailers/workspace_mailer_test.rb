# frozen_string_literal: true

require "test_helper"

class WorkspaceMailerTest < ActionMailer::TestCase
  test "welcome sends multipart email with text and html" do
    workspace = workspaces(:acme)
    email = WorkspaceMailer.welcome(workspace)

    assert_equal 2, email.parts.size
    assert email.parts.any? { |p| p.content_type.include?("text/plain") }
    assert email.parts.any? { |p| p.content_type.include?("text/html") }
  end

  test "welcome sends to workspace creator" do
    workspace = workspaces(:acme)
    email = WorkspaceMailer.welcome(workspace)

    assert_equal [ workspace.creator.email_address ], email.to
  end

  test "email_changed sends to both old and new addresses" do
    identity = global_identities(:alice)
    email = WorkspaceMailer.email_changed(identity, "old@example.com", "new@example.com")

    assert_equal [ "old@example.com", "new@example.com" ], email.to
  end

  test "email_changed deduplicates when old and new are same" do
    identity = global_identities(:alice)
    email = WorkspaceMailer.email_changed(identity, "same@example.com", "same@example.com")

    assert_equal [ "same@example.com" ], email.to
  end

  test "email_changed sends multipart email with text and html" do
    identity = global_identities(:alice)
    email = WorkspaceMailer.email_changed(identity, "old@example.com", "new@example.com")

    assert_equal 2, email.parts.size
    assert email.parts.any? { |p| p.content_type.include?("text/plain") }
    assert email.parts.any? { |p| p.content_type.include?("text/html") }
  end

  test "email_changed mentions old email in body" do
    identity = global_identities(:alice)
    email = WorkspaceMailer.email_changed(identity, "old@example.com", "new@example.com")

    assert_match "old@example.com", email.text_part.body.to_s
    assert_match "new@example.com", email.text_part.body.to_s
  end
end
