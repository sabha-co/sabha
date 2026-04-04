# frozen_string_literal: true

class Workspace::Snapshot < UntenantedRecord
  belongs_to :workspace
end
