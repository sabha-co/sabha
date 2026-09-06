# frozen_string_literal: true

module GlobalIdentity::Joinable
  extend ActiveSupport::Concern

  # Idempotently links this identity to a workspace. Safe to call repeatedly.
  # Returns the membership so callers can check `previously_new_record?`
  # to detect a fresh join vs. a no-op rejoin.
  #
  # If create_user! raises on a freshly-opened membership, destroy it so the
  # row cannot surface in the selector as a phantom workspace. Pre-existing
  # memberships are left alone.
  def join(tenant)
    transaction do
      lock!

      existing = workspace_memberships.find_by(tenant: tenant)
      if existing
        existing.create_user!
        return existing
      end

      raise GlobalIdentity::MembershipLimitReachedError if membership_limit_reached?

      workspace_memberships.create!(tenant: tenant).tap do |membership|
        begin
          membership.create_user!
        rescue ActiveRecord::RecordInvalid
          membership.destroy
          raise
        end
      end
    end
  end
end
