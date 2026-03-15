# frozen_string_literal: true

class Workspace
  class ExternalIdSequence < UntenantedRecord
    # Sequential ID generator for workspace external_ids
    #
    # Uses database row locking to ensure thread-safe ID generation.
    # IDs start at 1000001 (7 digits) for clean URL patterns.
    #
    # Usage:
    #   Workspace::ExternalIdSequence.next_id  # => 1000001, 1000002, ...

    INITIAL_VALUE = 1_000_100

    class << self
      def next_id
        with_lock do |sequence|
          sequence.increment!(:value).value
        end
      end

      private

        def with_lock
          transaction do
            sequence = lock.first_or_create!(value: initial_value)
            yield sequence
          end
        end

        def initial_value
          # Use highest existing external_id or default
          [ Workspace.maximum(:external_id) || 0, INITIAL_VALUE ].max
        end
    end
  end
end
