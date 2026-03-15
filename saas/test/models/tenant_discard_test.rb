# frozen_string_literal: true

require_relative "../test_helper"

class TenantDiscardTest < ActiveSupport::TestCase
  test "ApplicationJob discards TenantDoesNotExistError" do
    job_class = Class.new(ApplicationJob) do
      self.queue_adapter = :test

      def perform
        raise ActiveRecord::Tenanted::TenantDoesNotExistError, "gone"
      end
    end

    assert_nothing_raised do
      job_class.perform_now
    end
  end

  test "MailDeliveryJob discards TenantDoesNotExistError via mailer rescue_from" do
    # Stub a mailer action to raise TenantDoesNotExistError during delivery,
    # simulating what happens when a workspace is deleted after mail is enqueued.
    UserMailer.any_instance.stubs(:email_verification).raises(
      ActiveRecord::Tenanted::TenantDoesNotExistError, "gone"
    )

    user = User.new(email_address: "test@example.com")

    assert_nothing_raised do
      ActionMailer::MailDeliveryJob.perform_now(
        "UserMailer", "email_verification", "deliver_now", args: [ user ]
      )
    end
  end
end
