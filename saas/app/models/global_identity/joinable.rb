# frozen_string_literal: true

module GlobalIdentity::Joinable
  extend ActiveSupport::Concern

  # Idempotently links this identity to a workspace. Safe to call repeatedly:
  # find_or_create_by collapses retries into a single membership, and
  # WorkspaceMembership#create_user! reactivates or creates the per-tenant User
  # as needed. Returns the membership so callers can check `previously_new_record?`
  # to detect a fresh join vs. a no-op rejoin.
  #
  # If create_user! raises on a freshly-opened membership, destroy it: `user_active`
  # defaults to true on insert, so the row would otherwise surface in the workspace
  # selector (see WorkspaceMembership.user_active) as a phantom workspace the user
  # can't enter. Pre-existing memberships are left alone — they may be healthy from
  # a prior successful join or another in-flight retry.
  def join(tenant)
    workspace_memberships.find_or_create_by!(tenant: tenant).tap do |membership|
      begin
        membership.create_user!
      rescue ActiveRecord::RecordInvalid
        membership.destroy if membership.previously_new_record?
        raise
      end
    end
  end
end
