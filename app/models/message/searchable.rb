module Message::Searchable
  extend ActiveSupport::Concern

  included do
    after_create_commit  :create_in_index
    after_update_commit  :update_in_index
    after_destroy_commit :remove_from_index

    # Message::SearchIndex owns the engine-specific index (an FTS5 shadow table
    # on SQLite, a tsvector column on Postgres); this concern just declares the
    # lifecycle hooks and the scope and delegates the mechanics to it.
    scope :search, ->(query) { Message::SearchIndex.search(all, query) }
  end

  private
    def create_in_index
      Message::SearchIndex.add(self)
    end

    def update_in_index
      Message::SearchIndex.refresh(self)
    end

    def remove_from_index
      Message::SearchIndex.remove(self)
    end
end
