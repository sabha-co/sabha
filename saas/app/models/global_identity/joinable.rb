# frozen_string_literal: true

module GlobalIdentity::Joinable
  extend ActiveSupport::Concern

  # Idempotently links this identity to a workspace. Safe to call repeatedly.
  # Returns the membership so callers can check `previously_new_record?`
  # to detect a fresh join vs. a no-op rejoin.
  #
  # Coming back to a workspace you left counts toward the membership cap like
  # a new join; the identity row lock keeps two joins from both slipping under it.
  #
  # If create_user! raises on a freshly-opened membership, destroy it so the
  # row cannot surface in the selector as a phantom workspace. Pre-existing
  # memberships are left alone.
  def join(tenant)
    transaction do
      lock!

      membership = workspace_memberships.find_by(tenant: tenant)
      already_in = membership&.user_active?
      raise GlobalIdentity::MembershipLimitReachedError if !already_in && membership_limit_reached?

      if membership
        membership.tap(&:create_user!)
      else
        workspace_memberships.create!(tenant: tenant).tap do |membership|
          membership.create_user!
        rescue ActiveRecord::RecordInvalid
          membership.destroy
          raise
        end
      end
    end
  end
end
