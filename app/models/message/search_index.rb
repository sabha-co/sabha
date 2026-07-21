# Owns the full-text search index end to end — provisioning it, keeping it
# current, and querying it — so that everything engine-specific about search
# lives in one object. Message::Searchable just declares the callbacks and the
# scope and delegates here. The one adapter branch is #postgresql?.
#
# The index is deliberately kept out of db/schema.rb and out of a dated
# migration. A single schema file can't hold both an FTS5 virtual table (SQLite)
# and a tsvector column + GIN index (Postgres), and a version-gated migration
# would be stamped already-applied by db:schema:load and silently skipped on a
# fresh install — leaving it with no search index. So provisioning runs wherever
# a database is set up: enhanced onto db:prepare (boot and CI) and again in the
# test schema load (see test/test_helper.rb).
#
# ensure! is a strict no-op when the index already exists. Existing SQLite
# installs carry a populated message_search_index; recreating it errors. No data
# backfill runs there: a fresh install's messages table is empty, and migrating
# a populated table across engines is deferred work that must go through
# plain_text_body in Ruby, not raw HTML in SQL.
module Message::SearchIndex
  extend self

  # --- Provisioning ---

  def ensure!
    postgresql? ? ensure_postgresql! : ensure_sqlite!
  end

  # Whether the search index is present for the current adapter.
  def exists?
    postgresql? ? connection.column_exists?(:messages, :body_search) : sqlite_index_present?
  end

  # Empties the index without dropping it. The demo seed's reset wipes every
  # table in connection.tables, but an FTS5 virtual table isn't reported there
  # (see #sqlite_index_present?), so that loop skips the shadow table and its
  # rows would otherwise pile up as orphans across re-seeds. On Postgres the
  # tsvector lives on the messages row itself, so deleting the messages already
  # clears it — nothing to do here.
  def clear!
    return if postgresql?
    return unless exists?

    connection.execute "DELETE FROM message_search_index"
  end

  # --- Keeping the index current (called from Message::Searchable callbacks) ---

  def add(message)
    if postgresql?
      write_tsvector(message)
    else
      execute "insert into message_search_index(rowid, body) values (?, ?)", message.id, message.plain_text_body
    end
  end

  def refresh(message)
    if postgresql?
      write_tsvector(message)
    else
      execute "update message_search_index set body = ? where rowid = ?", message.plain_text_body, message.id
    end
  end

  def remove(message)
    # On Postgres the tsvector lives on the messages row itself, so a destroyed
    # message takes its index entry with it — nothing to clean up. SQLite's FTS5
    # shadow table is separate and needs the row removed explicitly.
    return if postgresql?

    execute "delete from message_search_index where rowid = ?", message.id
  end

  # --- Querying (backs the Message.search scope) ---
  #
  # Bare-token queries (callers strip everything but word characters first)
  # filtered against the index, ordered. plainto_tsquery is sufficient because
  # phrase/operator syntax never reaches here; the only cross-engine difference
  # is stopwords — Postgres's english config strips them, FTS5's porter keeps them.
  def search(relation, query)
    if postgresql?
      relation.where("messages.body_search @@ plainto_tsquery('english', ?)", query).ordered
    else
      relation.joins("join message_search_index idx on messages.id = idx.rowid").where("idx.body match ?", query).ordered
    end
  end

  # The one place the search backend branches on adapter.
  def postgresql?
    connection.adapter_name == "PostgreSQL"
  end

  private
    def connection
      Message.connection
    end

    def write_tsvector(message)
      execute "update messages set body_search = to_tsvector('english', ?) where id = ?", message.plain_text_body, message.id
    end

    def execute(*statement)
      connection.execute Message.sanitize_sql(statement)
    end

    def ensure_sqlite!
      return if sqlite_index_present?

      connection.execute "CREATE VIRTUAL TABLE message_search_index USING fts5(body, tokenize=porter)"
    end

    def ensure_postgresql!
      unless connection.column_exists?(:messages, :body_search)
        connection.add_column :messages, :body_search, :tsvector
      end

      connection.add_index :messages, :body_search,
        using: :gin, name: "index_messages_on_body_search", if_not_exists: true
    end

    # table_exists? does not report FTS5 virtual tables, so check the catalog.
    def sqlite_index_present?
      connection.select_value(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'message_search_index'"
      ).present?
    end
end
