# frozen_string_literal: true

# Support root-relative schema_dump paths in database.yml
#
# Rails assumes schema_dump values are relative to db/, so "saas/db/untenanted_schema.rb"
# becomes "db/saas/db/untenanted_schema.rb" which is wrong. This patch detects paths
# that aren't simple filenames and treats them as relative to Rails.root instead.
#
# rails/rails#56290 (merged Dec 2025) added support for absolute paths, but not
# relative paths with directories. Our schema_dump is "saas/db/untenanted_schema.rb"
# which is relative-with-directories, so the upstream fix doesn't help.
#
# Alternative: use an absolute path in database.yml to avoid this patch entirely:
#   schema_dump: <%= Rails.root.join("saas/db/untenanted_schema.rb") %>
#
# Adapted from Fizzy: https://github.com/rails/rails/pull/56290

module SchemaDumpPathExtension
  extend ActiveSupport::Concern

  class_methods do
    def schema_dump_path(db_config, format = db_config.schema_format)
      return ENV["SCHEMA"] if ENV["SCHEMA"]

      filename = db_config.schema_dump(format)
      return unless filename

      # If the path contains a directory separator, treat it as relative to Rails.root
      # rather than letting Rails prepend db/
      if filename.include?("/")
        Rails.root.join(filename).to_s
      else
        super
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Tasks::DatabaseTasks.include(SchemaDumpPathExtension)
end
