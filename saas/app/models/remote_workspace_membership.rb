# frozen_string_literal: true

# One person's entry for a self-hosted community in their sabha.co list. It
# records how the entry got there and where it sits in the selector, never a
# credential for the community.
class RemoteWorkspaceMembership < UntenantedRecord
  enum :source, %w[ added prompt shortcut sabha_cloud ].index_by(&:itself), validate: true

  belongs_to :global_identity, touch: true
  belongs_to :remote_workspace

  scope :visible, -> { where(hidden: false) }
  scope :alphabetically, -> { eager_load(:remote_workspace).order(RemoteWorkspace.arel_table[:name].lower) }
end
