# frozen_string_literal: true

require_relative "../../test_helper"

class Workspace::ExportTest < ActiveSupport::TestCase
  test "create_from_database! uploads a gzipped, sanitized snapshot to R2 and returns an Export with key+size" do
    captured_body = nil

    s3_client = mock
    s3_client.expects(:put_object).with do |args|
      assert_match(%r{\Aexports/\d+/\d{14}-[0-9a-f]+\.sqlite3\.gz\z}, args[:key])
      captured_body = args[:body].read
      args[:body].rewind
      true
    end
    Workspace::R2.stubs(:client).returns(s3_client)

    with_provisioned_workspace(name: "Export Model Test", creator: global_identities(:alice)) do |workspace|
      export = Workspace::Export.create_from_database!(workspace)

      assert_kind_of Workspace::Export, export
      assert export.key.start_with?("exports/#{workspace.external_id}/")
      assert export.size.positive?
      assert export.filename.end_with?(".sqlite3.gz")

      # Body is gzipped — magic bytes 0x1f 0x8b
      assert_equal "\x1f\x8b".b, captured_body.byteslice(0, 2).b

      # Decompress and verify it is a sanitized SQLite
      Tempfile.create([ "decoded", ".sqlite3" ]) do |decoded|
        decoded.binmode
        decoded.write(Zlib::GzipReader.new(StringIO.new(captured_body)).read)
        decoded.flush

        db = SQLite3::Database.new(decoded.path)
        begin
          assert db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='users'").any?
          non_null = db.execute("SELECT COUNT(*) FROM users WHERE workspace_membership_id IS NOT NULL").first.first
          assert_equal 0, non_null, "snapshot should have workspace_membership_id cleared"
        ensure
          db.close
        end
      end
    end
  end

  test "signed_url presigns against the export's key with a default 24h TTL" do
    # Stub R2.client so AWS SDK doesn't try real credential resolution
    # (IMDS lookup) when we instantiate the presigner.
    Workspace::R2.stubs(:client).returns(mock)

    presigner = mock
    presigner.expects(:presigned_url).with do |verb, **opts|
      assert_equal :get_object, verb
      assert_equal Workspace::R2.bucket, opts[:bucket]
      assert_equal "exports/123/abc.sqlite3.gz", opts[:key]
      assert_equal 24.hours.to_i, opts[:expires_in]
      true
    end.returns("https://r2.example/signed-url")
    Aws::S3::Presigner.expects(:new).returns(presigner)

    workspace = workspaces(:acme)
    export = Workspace::Export.new(workspace)
    export.instance_variable_set(:@key, "exports/123/abc.sqlite3.gz")

    assert_equal "https://r2.example/signed-url", export.signed_url
  end
end
