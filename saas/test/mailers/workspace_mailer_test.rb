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

  test "deleted sends to admin with workspace name" do
    email = WorkspaceMailer.deleted("My Workspace", "admin@example.com")

    assert_equal 2, email.parts.size
    assert_equal [ "admin@example.com" ], email.to
    assert_equal "Your workspace \"My Workspace\" has been deleted", email.subject
    assert_match "My Workspace", email.text_part.body.to_s
    assert_match "My Workspace", email.html_part.body.to_s
  end

  test "export_ready sends signed download URL to recipient" do
    workspace = workspaces(:acme)
    export = stub(
      signed_url: "https://r2.example/signed",
      filename: "sabha-workspace-1000001-20260502120000.sqlite3.gz",
      size: 1_500_000
    )

    email = WorkspaceMailer.export_ready(workspace, "admin@example.com", export)

    assert_equal [ "admin@example.com" ], email.to
    assert_equal "Your \"#{workspace.name}\" export is ready", email.subject
    assert_equal 2, email.parts.size
    assert_match "https://r2.example/signed", email.text_part.body.to_s
    assert_match "https://r2.example/signed", email.html_part.body.to_s
    assert_match "gunzip", email.text_part.body.to_s
    assert_match workspace.name, email.text_part.body.to_s
  end
end
