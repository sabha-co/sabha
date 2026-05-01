# frozen_string_literal: true

require_relative "../../test_helper"

class Workspace::PurgeExportJobTest < ActiveSupport::TestCase
  test "deletes the R2 object at the given key" do
    s3_client = mock
    s3_client.expects(:delete_object).with(bucket: Workspace::R2.bucket, key: "exports/1000001/abc.sqlite3.gz")
    Workspace::R2.stubs(:client).returns(s3_client)

    Workspace::PurgeExportJob.perform_now("exports/1000001/abc.sqlite3.gz")
  end

  test "swallows NoSuchKey when the object is already gone" do
    s3_client = mock
    s3_client.expects(:delete_object).raises(Aws::S3::Errors::NoSuchKey.new(nil, "not found"))
    Workspace::R2.stubs(:client).returns(s3_client)

    assert_nothing_raised do
      Workspace::PurgeExportJob.perform_now("exports/1000001/missing.sqlite3.gz")
    end
  end
end
