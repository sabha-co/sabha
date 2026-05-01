# frozen_string_literal: true

require_relative "../../test_helper"

class Workspace::ExportJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    # with_provisioned_workspace teardown calls Workspace::Backup.create_from_database!
    # via destroy_with_database! when R2 is configured. Stub it to a no-op so these
    # tests don't reach S3 during teardown.
    Workspace::Backup.stubs(:create_from_database!)
  end

  test "creates the export, schedules cleanup, and emails the recipient with the signed URL" do
    fake_export = stub(
      key: "exports/1000001/abc.sqlite3.gz",
      filename: "abc.sqlite3.gz",
      size: 4242,
      signed_url: "https://r2.example/signed"
    )

    with_provisioned_workspace(name: "Export Job Test", creator: global_identities(:alice)) do |workspace|
      Workspace::Export.expects(:create_from_database!).with(workspace).returns(fake_export)

      assert_enqueued_with(job: Workspace::PurgeExportJob, args: [ fake_export.key ]) do
        assert_emails 1 do
          Workspace::ExportJob.perform_now(workspace, "admin@example.com")
        end
      end

      delivery = ActionMailer::Base.deliveries.last
      assert_equal [ "admin@example.com" ], delivery.to
      assert_match "https://r2.example/signed", delivery.text_part.body.to_s
    end
  end

  test "schedules the purge before sending the email so a delivery failure still cleans up" do
    fake_export = stub(
      key: "exports/1000001/abc.sqlite3.gz",
      filename: "abc.sqlite3.gz",
      size: 4242,
      signed_url: "https://r2.example/signed"
    )

    with_provisioned_workspace(name: "Email Failure Test", creator: global_identities(:alice)) do |workspace|
      Workspace::Export.expects(:create_from_database!).with(workspace).returns(fake_export)

      doomed_delivery = mock
      doomed_delivery.expects(:deliver_now).raises(StandardError, "SES outage")
      WorkspaceMailer.expects(:export_ready).with(workspace, "admin@example.com", fake_export).returns(doomed_delivery)

      assert_enqueued_with(job: Workspace::PurgeExportJob, args: [ fake_export.key ]) do
        assert_raises(StandardError) do
          Workspace::ExportJob.perform_now(workspace, "admin@example.com")
        end
      end
    end
  end

  test "lets the underlying export error surface (no silent guard)" do
    with_provisioned_workspace(name: "Loud Failure Test", creator: global_identities(:alice)) do |workspace|
      Workspace::Export.expects(:create_from_database!).raises(StandardError, "R2 unreachable")

      assert_no_emails do
        assert_raises(StandardError, "R2 unreachable") do
          Workspace::ExportJob.perform_now(workspace, "admin@example.com")
        end
      end
    end
  end
end
