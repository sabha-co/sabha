# frozen_string_literal: true

# One person's entry for a self-hosted workspace in their sabha.co list. It
# records how the entry got there and where it sits in the selector, never a
# credential for the workspace.
class RemoteWorkspaceMembership < UntenantedRecord
  enum :source, %w[ added prompt shortcut sabha_cloud ].index_by(&:itself), validate: true

  belongs_to :global_identity, touch: true
  belongs_to :remote_workspace

  validates :remote_workspace, uniqueness: { scope: :global_identity }

  scope :visible, -> { where(hidden: false) }
  scope :consented, -> { where.not(consented_at: nil) }

  def consented?
    consented_at.present?
  end

  # sabha.co stops vouching for this person here until they approve again
  def revoke_consent!
    update!(consented_at: nil)
  end
end
