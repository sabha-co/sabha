# Keep the engine-specific full-text search DDL out of db/schema.rb dumps.
#
# Message::SearchIndex provisions the search index outside the schema (an FTS5
# virtual table on SQLite, a tsvector column + GIN index on Postgres). But with
# dump_schema_after_migration on (the dev/test default), a developer's
# db:migrate re-dumps schema.rb from the live database and would push whichever
# engine's search DDL into the shared schema — which then fails to load on the
# other engine. This strips only those lines, so ordinary migrations keep
# auto-dumping schema.rb normally.
module SearchIndexSchemaFilter
  # The tsvector column / its GIN index (Postgres) and the FTS5 virtual table
  # plus the comment header the SQLite dumper emits alongside it.
  SEARCH_DDL = /
    body_search
    | message_search_index
    | Virtual\ tables\ defined\ in\ this\ database
    | virtual\ tables\ may\ not\ work\ with\ other\ database\ engines
  /x

  def dump(stream)
    filtered = StringIO.new
    super(filtered)
    filtered.rewind
    filtered.each_line { |line| stream.write(line) unless line.match?(SEARCH_DDL) }
    stream
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::SchemaDumper.prepend(SearchIndexSchemaFilter)
end
