class Storage::Entry < ApplicationRecord
  belongs_to :recordable, polymorphic: true, optional: true

  scope :pending, ->(last_entry_id) { where.not(id: ..last_entry_id) if last_entry_id }

  def self.record(delta:, operation:, recordable: nil, blob: nil)
    return if delta.zero?
    return unless Sabha.saas?

    entry = create! \
      recordable_type: recordable&.class&.name,
      recordable_id: recordable&.id,
      blob_id: blob&.id,
      delta: delta,
      operation: operation,
      user_id: Current.user&.id,
      request_id: Current.request&.request_id

    # Current.account is memoized per-request; falls back to Account.sole
    # in background jobs where Current isn't set (e.g. reconciliation).
    (Current.account || Account.sole).materialize_storage_later

    entry
  end
end
