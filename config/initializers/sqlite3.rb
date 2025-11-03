module SQLite3Configuration
  private
    def configure_connection
      super

      if @config[:retries]
        retries = self.class.type_cast_config_to_integer(@config[:retries])
        raw_connection.busy_handler do |count|
          (count <= retries).tap { |result| sleep count * 0.001 if result }
        end
      end
    end
end

module SQLite3DumpConfiguration
  def structure_dump(filename, extra_flags)
    args = []
    args.concat(Array(extra_flags)) if extra_flags
    args << db_config.database

    ignore_tables = ActiveRecord::SchemaDumper.ignore_tables
    if ignore_tables.any?
      ignore_tables = connection.data_sources.select { |table| ignore_tables.any? { |pattern| pattern === table } }
      condition = ignore_tables.map { |table| connection.quote(table) }.join(", ")
      args << "SELECT sql || ';' FROM sqlite_master WHERE tbl_name NOT IN (#{condition}) ORDER BY tbl_name, type DESC, name"
    else
      args << ".schema --nosys"
    end
    run_cmd("sqlite3", args, filename)
  end
end

ActiveSupport.on_load :active_record do
  ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend SQLite3Configuration
  ActiveRecord::Tasks::SQLiteDatabaseTasks.prepend SQLite3DumpConfiguration
end
